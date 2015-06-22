request = require '../lib/request'
Contact = require '../models/contact'
Utils = require './utils'

# Account type and name of the created android contact account.
ACCOUNT_TYPE = 'io.cozy'
ACCOUNT_NAME = 'myCozy'


module.exports =

    testSyncContacts: (callback) ->
        # @initContactsInPhone (err) ->
        @syncContacts (err, cozyContacts) ->
            if err
                 console.log 'err'
                 console.log err
                 return callback err

            console.log cozyContacts
            return callback cozyContacts

        # navigator.contacts.find [navigator.contacts.fieldType.sourceId]
        # , (contacts) ->
        #     console.log "CONTACTS FROM PHONE : #{contacts.length}"
        #     console.log contacts

        #     # update data and change  version :
        #     c = contacts[0]
        #     c.note = new Date().toISOString()
        #     c.dirty = true
        #    # c.sync2 = '5d40cdecca9e84d8809679a2f21e54b4'
        #    # c.sync3 = new Date().toISOString()

        #     c.save callback, callback
        #     ,
        #         accountType: 'com.google'
        #         accountName: 'rogerdupondt@gmail.com'


        # , callback
        # , new ContactFindOptions "3e4ff6648ea6dd5c", false, [], 'com.google', 'rogerdupondt@gmail.com'




# #
    syncContacts: (callback) ->
        return callback null unless @config.get 'syncContacts'

        # Phone is right on conflict.
        # Contact sync has 3 phases
        # 1 - Phone2Pouch
        # 2 - Pouch <-> Couch (cozy)
        # 3 - Pouch2Phone.

        async.series [
            # @createAccount
                (cb) => @syncPhone2Pouch cb
                (cb) => @_syncToCozy cb
                (cb) => @syncFromCozyToPouchToPhone cb
            ], callback

    createAccount: (callback) =>
        navigator.contacts.createAccount ACCOUNT_TYPE, ACCOUNT_NAME
        , ->
            callback null
        , (err) ->
            callback err

    # Sync phone to pouch components

    _updateInPouch: (phoneContact, callback) ->
        async.parallel
            fromPouch: (cb) =>
                @db.get phoneContact.sourceId,  attachments: true, cb

            fromPhone: (cb) ->
                    Contact.cordova2Cozy phoneContact, cb
        , (err, res) =>
            return callback err if err

            contact = _.extend res.fromPouch, res.fromPhone

            if contact._attachments?.picture?
                picture = contact._attachments.picture

                if res.fromPouch._attachments?.picture?
                    oldPicture = res.fromPouch._attachments?.picture?
                    if oldPicture.data is picture.data
                        picture.revpos = oldPicture.revpos
                    else
                        picture.revpos = 1 + parseInt contact._rev.split('-')[0]

            @db.put contact, contact._id, contact._rev, (err, idNrev) =>
                if err
                    # if err.status is 409 # conflict, bad _rev
                        # Try again.
                        # return @_updateInPouch phoneContact, callback
                    # else
                    return callback err

                @_undirty phoneContact, idNrev, callback


    _createInPouch: (phoneContact, callback) ->
        Contact.cordova2Cozy phoneContact, (err, fromPhone) =>
            contact = _.extend
                docType: 'contact'
                tags: []
            , fromPhone

            if contact._attachments?.picture?
                contact._attachments.picture.revpos = 1

            @db.post contact, (err, idNrev) =>
                return callback err if err
                @_undirty phoneContact, idNrev, callback


    _undirty: (dirtyContact, idNrev, callback) ->
        # undirty and set id and rev on phone contact.
        dirtyContact.dirty = false
        dirtyContact.sourceId = idNrev.id
        dirtyContact.sync2 = idNrev.rev

        dirtyContact.save () ->
            callback null
        , callback
        ,
            accountType: ACCOUNT_TYPE
            accountName: ACCOUNT_NAME
            callerIsSyncAdapter: true

    # Delete remaining contacts in pouch.
    _deleteInPouch: (contactIds, callback) ->
        options =
            include_docs: true
            attachments: false
            keys: Object.keys contactIds

        @db.query 'Contacts', options, (err, res) =>
            return callback err if err

            async.each res.rows, (row, cb) =>
                toDelete =
                    docType: 'contact'
                    _id: row.doc._id
                    _rev: row.doc._rev
                    _deleted: true

                @db.put toDelete, toDelete._id, toDelete._rev
                , cb
            , callback


    # TODO : clean.
    syncPhone2Pouch: (callback) ->
        # No deleted flags... identify delete by list comparison
        # Go through each phoneContact,
        # mark pouchContacts
        # if dirty, updateorCreate pouchContact
        #
        # delete un-marked pouchContact

        # Get contacts list
        async.parallel
            pouchContacts: (cb) ->
                app.replicator.db.query 'Contacts', { include_docs: false, attachments: false }, cb

            # Get all contacts
            phoneContacts: (cb) ->
                navigator.contacts.find [navigator.contacts.fieldType.id]
                , (contacts) ->
                    console.log "CONTACTS FROM PHONE : #{contacts.length}"
                    console.log contacts

                    cb null, contacts

                , cb
                , new ContactFindOptions "", true, [], ACCOUNT_TYPE, ACCOUNT_NAME
        , (err, res) =>
            return callback err if err

            pouchContactIds = Utils.array2Hash res.pouchContacts.rows, 'id'

            async.each res.phoneContacts, (phoneContact, cb) =>
                delete pouchContactIds[phoneContact.sourceId]
                if phoneContact.dirty
                    if phoneContact.sourceId
                        @_updateInPouch phoneContact, cb
                    else
                        @_createInPouch phoneContact, cb
                else
                    cb() # skip

            , (err) =>
                return callback err if err
                @_deleteInPouch pouchContactIds, callback


    _syncToCozy: (callback) =>
        # Get contacts from the cozy (couch -> pouch replication)
        console.log "checkpointedPush: #{app.replicator.config.get 'contactsPushCheckpointed'}"
        replication = app.replicator.db.replicate.to app.replicator.config.remote,
            batch_size: 20
            batches_limit: 5
            filter: (doc) ->
                return doc? and doc.docType?.toLowerCase() is 'contact' # and
                    #not doc._deleted # TODO ! should not need this ! # Pb with attachments ?
            live: false
            #since: app.replicator.config.get 'contactsPushCheckpointed'

        replication.on 'change', (e) =>
            console.log "Replication Change"
            console.log e
        replication.on 'error', callback
        replication.on 'complete', (result) =>
            console.log "REPLICATION COMPLETED contacts"
            console.log result
            app.replicator.config.save contactsPushCheckpointed: result.last_seq,  callback

    _saveContactInPhone: (cozyContact, phoneContact, callback) =>
        toSave = Contact.cozy2Cordova cozyContact

        if phoneContact
            toSave.id = phoneContact.id
            toSave.rawId = phoneContact.rawId

        options =
            accountType: ACCOUNT_TYPE
            accountName: ACCOUNT_NAME
            callerIsSyncAdapter: true
            resetFields: true

        console.log JSON.stringify toSave, null, 2
        toSave.save (contact)->
            console.log contact

            callback null, contact
        , callback, options


    _applyChangeToPhone: (docs, callback) ->
        getBySourceId = (sourceId, cb) ->
            console.log "get contact: #{sourceId}"
            navigator.contacts.find [navigator.contacts.fieldType.sourceId]
                , (contacts) ->
                    console.log "CONTACTS FROM PHONE : #{contacts.length}"
                    console.log contacts
                    cb null, contacts[0]
                , cb
                , new ContactFindOptions sourceId, false, [], ACCOUNT_TYPE, ACCOUNT_NAME

        async.each docs, (doc, cb) =>
            getBySourceId doc._id, (err, contact) =>
                return cb err if err

                if doc._deleted
                    contact.remove (-> cb()), cb, callerIsSyncAdapter: true

                else
                    @_saveContactInPhone doc, contact, cb
        , (err) ->
            console.log "done changes"
            callback err


    syncFromCozyToPouchToPhone: (callback) ->
        # Get contacts from the cozy (couch -> pouch replication)
        console.log "checkpointedPull: #{app.replicator.config.get 'contactsPullCheckpointed'}"
        replication = @db.replicate.from @config.remote,
            batch_size: 20
            batches_limit: 5
            filter: (doc) ->
                return doc? and doc.docType?.toLowerCase() is 'contact' # and
                    #not doc._deleted # TODO ! should not need this ! # Pb with attachments ?
            live: false
            since: @config.get 'contactsPullCheckpointed'

        replication.on 'change', (e) =>
            console.log "Replication Change"
            console.log e
            @_applyChangeToPhone e.docs, ->

        replication.on 'error', callback
        replication.on 'complete', (result) =>
            console.log "REPLICATION COMPLETED contacts"
            console.log result
            @config.save contactsPullCheckpointed: result.last_seq, callback

    # Initial replication task.
    initContactsInPhone: (callback) ->
        @createAccount (err) =>
            # Fetch contacs from view all of contact app.
            request.get @config.makeUrl("/_design/contact/_view/all/")
            , (err, res, body) =>
                return callback err if err
                return callback null unless body.rows?.length

                async.mapSeries body.rows, (row, cb) =>
                    doc = row.value
                    # fetch attachments if exists.
                    if doc._attachments?.picture?
                        request.get @config.makeUrl("/#{doc._id}?attachments=true")
                        # request.get @config.makeUrl("/#{doc._id}/picture")
                        , (err, res, body) ->
                            return cb err if err
                            cb null, body
                    else
                        cb null, doc
                , (err, docs) =>
                    return callback err if err

                    async.mapSeries docs, (doc, cb) =>
                        @db.put doc, 'new_edits':false, cb

                    , (err, contacts) =>
                        return callback err if err
                        @_applyChangeToPhone docs, callback