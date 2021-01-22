const fs = require("fs")
const path = require('path');
const Web3 = require("web3")
const HDWalletProvider = require('@truffle/hdwallet-provider');
const mnemonicRopsten = fs.readFileSync(path.join(__dirname, '..', '.secret.ropstenDeployer')).toString().trim();
const rpcWs = fs.readFileSync(path.join(__dirname, '..', '.rpcWs')).toString().trim();
const deployer = fs.readFileSync(path.join(__dirname, '..', '.deployer')).toString().trim();

const options = {
    timeout: 30000, // ms

    // // Useful for credentialed urls, e.g: ws://username:password@localhost:8546
    // headers: {
    //     authorization: 'Basic username:password'
    // },

    clientConfig: {
        // Useful if requests are large
        maxReceivedFrameSize: 100000000,   // bytes - default: 1MiB
        maxReceivedMessageSize: 100000000, // bytes - default: 8MiB

        // Useful to keep a connection alive
        keepalive: true,
        keepaliveInterval: 60000 // ms
    },

    // Enable auto reconnection
    reconnect: {
        auto: true,
        delay: 5000, // ms
        maxAttempts: 5,
        onTimeout: false
    }
};

let web3 = new Web3(
    new Web3.providers.WebsocketProvider(rpcWs, options)
);

let web3HD = new Web3(
    new HDWalletProvider({
        privateKeys: [mnemonicRopsten],
        providerOrUrl: rpcWs
    })
)

module.exports.web3 = web3;
module.exports.web3HD = web3HD;
module.exports.deployer = deployer;
