PouchDB = require 'pouchdb'
log = require("./persistent_log")
    prefix: "Database"
    date: true

class Database

    @REPLICATE_DB: 'cozy-files.db'
    @LOCAL_DB: 'cozy-photos.db'

    # Create databases
    #
    # adapter:
    #   'websql': actual database
    #
    # To test:
    #   options = db: require 'memdown'
    constructor: (options = adapter: 'websql', location: 'default') ->
        log.debug 'constructor', options

        @replicateDb = new PouchDB Database.REPLICATE_DB, options
        @localDb = new PouchDB Database.LOCAL_DB, options


    setRemoteDatabase: (cozyUrl) ->
        log.debug "setRemoteDatabase"

        @remoteDb = new PouchDB "#{cozyUrl}/replication"


    destroy: ->
        log.debug "destroy"

        @replicateDb.destroy()
        @localDb.destroy()
        @remoteDb.destroy() if @remoteDb


module.exports = Database
