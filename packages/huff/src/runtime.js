/* eslint-disable no-restricted-syntax */
const BN = require('bn.js');
const VM = require('ethereumjs-vm');
const Trie = require('merkle-patricia-tree');
const StateManager = require('ethereumjs-vm/dist/stateManager');
const { decode } = require('rlp');

const newParser = require('./parser');
const utils = require('./utils');
const { opcodes } = require('./opcodes/opcodes');

function toBytes32(input, padding = 'left') {
    // assumes hex format
    let s = input;
    if (s.length > 64) {
        throw new Error(`string ${input} is more than 32 bytes long!`);
    }
    while (s.length < 64) {
        if (padding === 'left') {
            // left pad to hash a number. Right pad to hash a string
            s = `0${s}`;
        } else {
            s = `${s}0`;
        }
    }
    return s;
}

function processMemory(bnArray) {
    const buffer = [];
    for (const { index, value } of bnArray) {
        const hex = toBytes32(value.toString(16));
        for (let i = 0; i < hex.length; i += 2) {
            buffer[i / 2 + index] = parseInt(`${hex[i]}${hex[i + 1]}`, 16);
        }
    }
    return buffer;
}

function getPushOp(hex) {
    const data = utils.formatEvenBytes(hex);
    const opcode = utils.toHex(95 + data.length / 2);
    return `${opcode}${data}`;
}

function encodeMemory(memory) {
    return memory.reduce((bytecode, { index, value }) => {
        const word = getPushOp(value.toString(16));
        const memIndex = getPushOp(Number(index).toString(16));
        return bytecode + `${word}${memIndex}${opcodes.mstore}`;
    }, '');
}

function encodeStack(stack) {
    return stack.reduce((bytecode, word) => {
        const value = getPushOp(word.toString(16));
        return bytecode + `${value}`;
    }, '');
}

function encodeState(state) {
    return state.reduce((bytecode, { slot, value }) => {
        const word = getPushOp(value.toString(16));
        const slotIndex = getPushOp(Number(slot).toString(16));
        return bytecode + `${word}${slotIndex}${opcodes.sstore}`;
    }, '');
}

function runCode(vm, bytecode, calldata, sourcemapOffset = 0, sourcemap = [], callvalue = 0) {
    return new Promise((resolve, reject) => {
        vm.runCode(
            {
                code: Buffer.from(bytecode, 'hex'),
                gasLimit: Buffer.from('ffffffff', 'hex'),
                data: calldata ? processMemory(calldata) : null,
                value: new BN(callvalue),
            },
            (err, results) => {
                if (err) {
                    console.log(results.runState.programCounter);
                    console.log(sourcemap[results.runState.programCounter - sourcemapOffset]);
                    return reject(err);
                }
                return resolve(results);
            },
        );
    });
}

function Runtime(filename, path, debug = false) {
    const { inputMap, macros, jumptables } = newParser.parseFile(filename, path);
    return async function runMacro(
        macroName,
        { stack = [], memory = [], state = [], calldata = null, callvalue = 0, baseTrie = false },
    ) {
        const memoryCode = encodeMemory(memory);
        const stackCode = encodeStack(stack);
        const stateCode = encodeState(state);
        const initCode = `${memoryCode}${stackCode}${stateCode}`;
        const initGasEstimate = memory.length * 9 + stack.length * 3 + state.length * 20006;
        const offset = initCode.length / 2;
        const {
            data: { bytecode: macroCode, sourcemap },
        } = newParser.processMacro(macroName, offset, [], macros, inputMap, jumptables); // prettier-ignore
        const bytecode = `${initCode}${macroCode}`;
        const vm = new VM({
            hardfork: 'constantinople',
            stateManager: state.length > 0 || baseTrie ? new StateManager({ trie: new Trie() }) : undefined,
        });
        const {
            runState: { stack: outStack, memory: outMemory, returnValue, gasLimit, gasLeft, stateManager, address },
        } = await runCode(vm, bytecode, calldata, offset, sourcemap, callvalue);
        const gasSpent = gasLimit
            .sub(gasLeft)
            .subn(initGasEstimate)
            .toString(10);
        if (debug) {
            console.log('code size = ', macroCode.length / 2);
            console.log('gas consumed = ', gasSpent);
        }
        const _outState = await new Promise((resolve, reject) =>
            stateManager.dumpStorage(address, (_state) => (typeof _state == Error ? reject : resolve)(_state)),
        );
        const outState = Object.keys(_outState).reduce((out, k) => {
            return [
                ...out,
                {
                    slot: parseInt(k, 16).toString(16),
                    value: decode(Buffer.from(_outState[k], 'hex')).toString('hex'),
                },
            ];
        }, []);
        return {
            gas: gasSpent,
            stack: outStack,
            memory: outMemory,
            returnValue,
            bytecode: macroCode,
            state: outState,
        };
    };
}

module.exports = Runtime;
