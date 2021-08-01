#!/usr/bin/env node
'use strict';

/**
 * Prepare Livescript environment with SourceMap support.
 */
var livescript = require('livescript');
var source_map_support = require('source-map-support');
source_map_support.install();

/**
 * Install module-loading hook.
 */
var yapRequireHook = require('./modules/yap-require-hook');
yapRequireHook.install();

if (!global.yapContext) {
    var preloads = {yapRequireHook}
    global.yapContext = {module, preloads};
}

/**
 * Initialize Yapps environment.
 */
var yapps = require('./modules/yapps');
yapps.init(__filename);

/**
 * Initialize Logger.
 */
var {DBG, INFO, ERR} = global.getLogger(__filename);

/**
 * Create an app for RDS Agent, and load related plugin modules.
 */
var app = yapps.createApp('base', {a: 1, b: 2});
app.addPlugin(require('./src/plugins/system-info'));
app.addPlugin(require('./src/plugins/system-helpers'));
app.addPlugin(require('./src/plugins/profile-storage'));
app.addPlugin(require('./src/wstty/services/http-by-server'));
app.addPlugin(require('./src/wstty/services/bash-by-server'));
app.addPlugin(require('./src/wstty/services/file-mgr'));
app.addPlugin(require('./src/wstty/wstty-client'));
app.init((err) => {
    if (err) {
        return ERR(err, "failed to initialize app");
    }
    else {
        return DBG("started");
    }
});