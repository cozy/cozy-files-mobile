compareVersions = require('../lib/compare_versions').compareVersions

log = require('../lib/persistent_log')
    date: true
    processusTag: "Init"

module.exports = class Init

    _.extend Init.prototype, Backbone.Events
    _.extend Init.prototype, Backbone.StateMachine

    # Override this function to use it as initialize.
    startStateMachine: ->
        @initialize()
        Backbone.StateMachine.startStateMachine.bind(@)(arguments)

    initialize: ->
        @migrationStates = {}

        @listenTo @, 'transition', (leaveState, enterState) ->
            log.info 'Transition from state "'+leaveState+'" to state "'+enterState+'"'


    initMigration: ->
        oldVersion = app.replicator.config.get 'appVersion'
        for version, migration of @migrations
            if compareVersions(version, oldVersion) <= 0
                break
            for state in migration.states
                @migrationStates[state] = true

        @trigger 'migrationInited'


    states:
        # States naming convention :
        # - a : application start.
        # - n : normal start
        # - f : first start
        # - m : migration start
        # - s : service start
        # - sm : migration in service start

        # Application

        # First commons steps
        aDeviceLocale: enter: ['setDeviceLocale']
        aInitFileSystem: enter: ['initFileSystem']
        aInitDatabase: enter: ['initDatabase']
        aInitConfig: enter: ['initConfig']

        # Normal (n) states
        nPostConfigInit: enter: ['postConfigInit']
        nQuitSplashScreen: enter: ['quitSplashScreen']


        # Migration (m) states
        migrationInit: enter: ['initMigration']
        mLocalDesignDocuments: enter: ['upsertLocalDesignDocuments']
        mCheckPlatformVersions: enter: ['checkPlatformVersions']
        mQuitSplashScreen: enter: ['quitSplashScreen']
        mPermissions: enter: ['getPermissions']
        mConfig: enter: ['config']
        mRemoteRequest: enter: ['putRemoteRequest']
        mUpdateVersion: enter: ['updateVersion']
        mPostConfigInit: enter: ['postConfigInit']


        # First start (f) states
        fQuitSplashScreen: enter: ['quitSplashScreen'] # RUN
        fLogin: enter: ['login']
        fPermissions: enter: ['getPermissions']
        fDeviceName: enter: ['setDeviceName']
        fConfig: enter: ['saveState', 'config']
        fFirstSyncView: enter: ['firstSyncView'] # RUN
        fLocalDesignDocuments: enter: ['upsertLocalDesignDocuments']
        fRemoteRequest: enter: ['putRemoteRequest']
        fPostConfigInit: enter: ['postConfigInit'] # RUN
        fSetVersion: enter: ['updateVersion']

        fInitialFilesReplication: enter: ['initialFilesReplication']
        fInitContacts: enter: ['saveState', 'initContacts']
        fInitCalendars: enter: ['saveState', 'initCalendars']
        fUpdateIndex: enter: ['saveState', 'updateIndex']


        # First start error steps
        # 1 error before FirstSync End. --> Go to config.
        f1QuitSplashScreen: enter: ['quitSplashScreen'] # RUN

        # 2 error after File sync
        f2QuitSplashScreen: enter: ['quitSplashScreen']
        f2FirstSyncView: enter: ['firstSyncView'] # RUN
        f2PostConfigInit: enter: ['postConfigInit'] # RUN

        # 3 error after contacts sync
        f3QuitSplashScreen: enter: ['quitSplashScreen']
        f3FirstSyncView: enter: ['firstSyncView'] # RUN
        f3PostConfigInit: enter: ['postConfigInit'] # RUN

        # 4 error after calendars sync
        f4QuitSplashScreen: enter: ['quitSplashScreen']
        f4FirstSyncView: enter: ['firstSyncView'] # RUN
        f4PostConfigInit: enter: ['postConfigInit'] # RUN


        # Last commons steps
        aLoadFilePage: enter: ['saveState', 'setListeners', 'loadFilePage']
        aBackup: enter: ['backup']


        # Service
        sInitFileSystem: enter: ['initFileSystem']
        sInitDatabase: enter: ['initDatabase']
        sInitConfig: enter: ['sInitConfig']

        sPostConfigInit: enter: ['postConfigInit']
        sBackup: enter: ['sBackup']
        sSync: enter: ['sSync']
        sQuit: enter: ['sQuit']

        # Service Migration (m) states
        smMigrationInit: enter: ['initMigration']
        smLocalDesignDocuments: enter: ['upsertLocalDesignDocuments']
        smCheckPlatformVersions: enter: ['checkPlatformVersions']
        smQuitSplashScreen: enter: ['quitSplashScreen']
        smPermissions: enter: ['getPermissions']
        smConfig: enter: ['config']
        smRemoteRequest: enter: ['putRemoteRequest']
        smUpdateVersion: enter: ['updateVersion']


    transitions:
        # Help :
        # initial_state: event: end_state

        # Start application
        'init':
            'startApplication': 'aDeviceLocale'
            'startService': 'sInitFileSystem'
        'aDeviceLocale': 'deviceLocaleSetted': 'aInitFileSystem'
        'aInitFileSystem': 'fileSystemReady': 'aInitDatabase'
        'aInitDatabase': 'databaseReady': 'aInitConfig'
        'aInitConfig':
            'configured': 'nPostConfigInit' # Normal start
            'newVersion': 'migrationInit' # Migration
            'notConfigured': 'fQuitSplashScreen' # First start
            # First start error
            'goTofConfig': 'f1QuitSplashScreen'
            'goTofInitContacts': 'f2QuitSplashScreen'
            'goTofInitCalendars': 'f3QuitSplashScreen'
            'goTofUpdateIndex': 'f4QuitSplashScreen'

        # Normal start
        'nPostConfigInit': 'initsDone': 'nQuitSplashScreen'
        'nQuitSplashScreen': 'viewInitialized': 'aLoadFilePage'
        'aLoadFilePage': 'onFilePage': 'aBackup'

        # Migration
        'migrationInit': 'migrationInited': 'mLocalDesignDocuments'
        'mLocalDesignDocuments':
            'localDesignUpToDate': 'mCheckPlatformVersions'
        'mCheckPlatformVersions': 'validPlatformVersions': 'mQuitSplashScreen'
        'mQuitSplashScreen': 'viewInitialized': 'mPermissions'
        'mPermissions': 'getPermissions': 'mConfig'
        'mConfig': 'configDone': 'mRemoteRequest'
        'mRemoteRequest': 'putRemoteRequest': 'mUpdateVersion'
        'mUpdateVersion': 'versionUpToDate': 'mPostConfigInit'
        'mPostConfigInit': 'initsDone': 'aLoadFilePage' # Regular start.

        # First start
        'fQuitSplashScreen': 'viewInitialized': 'fLogin'
        'fLogin': 'validCredentials': 'fPermissions'
        'fPermissions': 'getPermissions': 'fDeviceName'
        'fDeviceName': 'deviceCreated': 'fConfig'
        'fConfig': 'configDone': 'fFirstSyncView'
        'fFirstSyncView': 'firstSyncViewDisplayed': 'fLocalDesignDocuments'
        'fLocalDesignDocuments': 'localDesignUpToDate': 'fRemoteRequest'
        'fRemoteRequest': 'putRemoteRequest':'fSetVersion'
        'fSetVersion': 'versionUpToDate': 'fPostConfigInit'
        'fPostConfigInit': 'initsDone': 'fInitialFilesReplication'
        'fInitialFilesReplication': 'filesReplicationInited': 'fInitContacts'
        'fInitContacts': 'contactsInited': 'fInitCalendars'
        'fInitCalendars': 'calendarsInited': 'fUpdateIndex'
        'fUpdateIndex': 'indexUpdated': 'aLoadFilePage'

        # First start error transitions
        # 1 error after before FirstSync End. --> Go to config.
        'f1QuitSplashScreen': 'viewInitialized': 'fConfig'

        # 2 error after File sync
        'f2QuitSplashScreen': 'viewInitialized': 'f2FirstSyncView'
        'f2FirstSyncView': 'firstSyncViewDisplayed': 'f2PostConfigInit'
        'f2PostConfigInit': 'initsDone': 'fInitContacts'

        # 3 error after Contacts sync
        'f3QuitSplashScreen': 'viewInitialized': 'f3FirstSyncView'
        'f3FirstSyncView': 'firstSyncViewDisplayed': 'f3PostConfigInit'
        'f3PostConfigInit': 'initsDone': 'fInitCalendars'

        # 4 error after Calendars sync
        'f4QuitSplashScreen': 'viewInitialized': 'f4FirstSyncView'
        'f4FirstSyncView': 'firstSyncViewDisplayed': 'f4PostConfigInit'
        'f4PostConfigInit': 'initsDone': 'fUpdateIndex'


        # Start Service
        'sInitFileSystem': 'fileSystemReady': 'sInitDatabase'
        'sInitDatabase': 'databaseReady': 'sInitConfig'
        'sPostConfigInit': 'initsDone': 'sBackup'
        'sBackup': 'backupDone': 'sSync'
        'sSync': 'syncDone': 'sQuit'
        'sInitConfig':
            'configured': 'sPostConfigInit' # Normal start
            'newVersion': 'smMigrationInit' # Migration

        # Migration in service
        'smMigrationInit': 'migrationInited': 'smLocalDesignDocuments'
        'smLocalDesignDocuments':
            'localDesignUpToDate': 'smCheckPlatformVersions'
        'smCheckPlatformVersions': 'validPlatformVersions': 'smPermissions'
        'smPermissions': 'getPermissions': 'smConfig'
        'smConfig': 'configDone': 'smRemoteRequest'
        'smRemoteRequest': 'putRemoteRequest': 'smUpdateVersion'
        'smUpdateVersion': 'versionUpToDate': 'sPostConfigInit'


    # Enter state methods.
    setDeviceLocale: ->
        app.setDeviceLocale @getCallbackTriggerOrQuit 'deviceLocaleSetted'


    initFileSystem: ->
        app.replicator.initFileSystem \
            @getCallbackTriggerOrQuit 'fileSystemReady'


    initDatabase: ->
        app.replicator.initDB  @getCallbackTriggerOrQuit 'databaseReady'


    initConfig: ->
        app.replicator.initConfig (err, config) =>
            return @exitApp err if err
            if config.remote
                # Check last state
                # If state is "ready" -> newVersion ? newVersion : configured
                # Else : go to this state (with preconditions checks ?)
                lastState = config.get('lastInitState') or 'aLoadFilePage'

                # Watchdog
                if lastState not in ['aLoadFilePage', 'fConfig',
                        'fInitContacts', 'fInitCalendars', 'fUpdateIndex']
                    return @trigger 'goTofConfig'

                if lastState is 'aLoadFilePage' # Previously in normal start.
                    if config.isNewVersion()
                        @trigger 'newVersion'
                    else
                        @trigger 'configured'
                else # In init.
                    @trigger "goTo#{lastState}"


            else
                @trigger 'notConfigured'

    # Normal start
    postConfigInit: ->
        app.postConfigInit @getCallbackTriggerOrQuit 'initsDone'

    backup: ->
        app.replicator.backup {}, (err) -> log.error err if err
        @trigger 'backupStarted'

    quitSplashScreen: ->
        app.layout.quitSplashScreen()
        Backbone.history.start()
        @trigger 'viewInitialized'

    setListeners: ->
        app.setListeners()

    loadFilePage: ->
        app.router.navigate 'folder/', trigger: true
        app.router.once 'collectionfetched', => @trigger 'onFilePage'


    # Migration
    upsertLocalDesignDocuments: ->
        return if @passUnlessInMigration 'localDesignUpToDate'

        app.replicator.upsertLocalDesignDocuments @getCallbackTriggerOrQuit 'localDesignUpToDate'


    checkPlatformVersions: ->
        return if @passUnlessInMigration 'validPlatformVersions'
        app.replicator.checkPlatformVersions \
            @getCallbackTriggerOrQuit 'validPlatformVersions'


    getPermissions: ->
        return if @passUnlessInMigration 'getPermissions'
        if app.replicator.config.hasPermissions()
            @trigger 'getPermissions'
        else if @currentState is 'smPermissions'
            app.startMainActivity 'smPermissions'
        else
            app.router.navigate 'permissions', trigger: true


    putRemoteRequest: ->
        return if @passUnlessInMigration 'putRemoteRequest'

        app.replicator.putRequests @getCallbackTriggerOrQuit 'putRemoteRequest'

    updateVersion: ->
        app.replicator.config.updateVersion \
        @getCallbackTriggerOrQuit 'versionUpToDate'


    # First start
    login: ->
        app.router.navigate 'login', trigger: true

    setDeviceName: -> app.router.navigate 'device-name-picker', trigger: true

    config: ->
        return if @passUnlessInMigration 'configDone'
        if @currentState is 'smConfig'
            app.startMainActivity 'smConfig'
        else
            app.router.navigate 'config', trigger: true

    updateCozyLocale: -> app.replicator.updateLocaleFromCozy \
        @getCallbackTriggerOrQuit 'cozyLocaleUpToDate'

    firstSyncView: ->
        app.router.navigate 'first-sync', trigger: true
        @trigger 'firstSyncViewDisplayed'


    initialFilesReplication: ->
        app.replicator.initialFilesReplication \
            @getCallbackTriggerOrQuit 'filesReplicationInited'


    initContacts: ->
        app.replicator.initContactsInPhone \
            @getCallbackTriggerOrQuit 'contactsInited'

    initCalendars: ->
        app.replicator.initEventsInPhone \
            @getCallbackTriggerOrQuit 'calendarsInited'

    updateIndex: ->
        app.replicator.updateIndex @getCallbackTriggerOrQuit 'indexUpdated'

    ###########################################################################
    # Service
    sInitConfig: ->
        app.replicator.initConfig (err, config) =>
            return exitApp err if err
            return exitApp 'notConfigured' unless config.remote


            # Check last state
            # If state is "ready" -> newVersion ? newVersion : configured
            # Else : go to this state (with preconditions checks ?)
            lastState = config.get('lastInitState') or 'aLoadFilePage'

            if lastState is 'aLoadFilePage' # Previously in normal start.
                if config.isNewVersion()
                    @trigger 'newVersion'
                else
                    @trigger 'configured'
            else # In init.
                return exitApp "notConfigured: #{lastState}"
    sBackup: ->
        app.replicator.backup background: true
        , @getCallbackTriggerOrQuit 'backupDone'

    sSync: ->
        app.replicator.sync background: true
        , (err) =>
            @getCallbackTriggerOrQuit('syncDone')(err)

    sQuit: ->
        app.exit()

    ###########################################################################
    # Tools
    saveState: ->
        app.replicator.config.save lastInitState: @currentState
        , (err, config) -> log.warn err if err

    getCallbackTriggerOrQuit: (eventName) ->
        (err) =>
            if err
                app.exit err
            else
                @trigger eventName


    passUnlessInMigration: (event) ->
        state = @currentState

        # Convert service states.
        if state.indexOf('s') is 0
            state = state.slice 1

        if state.indexOf('m') is 0 and state not of @migrationStates
            log.info "Skip state #{state} during migration so fire #{event}."
            @trigger event
            return true
        else
            return false


    # Migrations

    migrations:
        '0.1.19':
            # Check cozy-locale, new view in the cozy, new permissions.
            states: ['mPermissions', 'mRemoteRequest']
        '0.1.18': states: []
        '0.1.17': states: []
        '0.1.16': states: []
        '0.1.15':
            # New routes, calendar sync.
            states: ['mCheckPlatformVersions', 'mPermissions',
                'mConfig', 'mRemoteRequest']