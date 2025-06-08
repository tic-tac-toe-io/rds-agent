/**
 * Copyright (c) 2019-2025 T2T Inc. All rights reserved
 * 
 *  https://www.t2t.io
 *  https://tic-tac-toe.io
 * 
 * Taipei, Taiwan
 */
'use strict';

const path = require('node:path');
const { promises: fs } = require("fs");
const { setTimeout: sleep } = require('timers/promises');
const {WARN} = global.getLogger(__filename);


const TTT_SYSTEM_FILEPATH = '/tmp/ttt_system';


async function readTttSystemFile(remainingAttempts) {
  try {
    const text = await fs.readFile(TTT_SYSTEM_FILEPATH, 'utf8');
    return text;
  } catch (error) {
    if (error.code === 'ENOENT') {
      WARN(`TTT system file does not exist at ${TTT_SYSTEM_FILEPATH} ... Attempt ${remainingAttempts}`);
      return null; // File does not exist
    }
    WARN(`Error reading TTT system file: ${error.message}... Attempt ${remainingAttempts}`);
    return null; // Other errors
  }
}



function getTttSystem(max_attempts, callback) {

  // let max_attempts = process.env.TTT_SYSTEM_MAX_ATTEMPTS || 30;
  // max_attempts = parseInt(max_attempts, 30);
  // if (isNaN(max_attempts) || max_attempts <= 0) {
  //   max_attempts = 10; // Default to 10 attempts if invalid
  // }

  setImmediate(async () => {
    let tttSystem = null;
    let attempts = 0;

    while (attempts < max_attempts) {
      tttSystem = await readTttSystemFile(max_attempts - attempts);
      if (tttSystem) {
        break; // Exit loop if file is read successfully
      }
      attempts++;
      await sleep(1000); // Wait for 1 second before retrying
    }
    if (tttSystem) {
      return callback(null, tttSystem);
    }
    else {
      return callback(new Error('Failed to read TTT system file after multiple attempts'));
    }
  });
}


module.exports = exports = getTttSystem;