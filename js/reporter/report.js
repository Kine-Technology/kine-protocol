const fs = require("fs")
const {web3, web3HD, deployer} = require("../web3Instance")
const myPrivateKey = fs.readFileSync('../../.secret.ropstenDeployer').toString().trim();
const BigNumber = require("bignumber.js");

const abiJson = require("../../build/contracts/Kaptain.json")
const addressObj = require("../../network/ropsten.json")
// const addressObj = require("../../network/ropsten-uat.json")

let kaptain = new web3HD.eth.Contract(abiJson.abi, addressObj.Kaptain.address);
let kaptain1 = new web3.eth.Contract(abiJson.abi, addressObj.Kaptain.address);

post();

async function post() {
    let priceData = {
        prices: {
            "KINE": 2.8
        },
        symbols: ['KINE']
    };
    let vaultKusdDelta = new BigNumber(0);
    let isKusdIncreased = false;
    let nonce = await kaptain1.methods.reporterNonce().call();
    // let nonce = 0;

    let signedArr = sign(encode('prices', Math.floor(+new Date / 1000), priceData.prices), myPrivateKey);
    let messages = signedArr.map(({message}) => message);
    let signatures = signedArr.map(({signature}) => signature);
    let symbols = priceData.symbols;

    console.log([messages, signatures, symbols, vaultKusdDelta, isKusdIncreased]);

    signedArr = sign(web3.eth.abi.encodeParameters(
        // bytes[] memory messages, bytes[] memory signatures, string[] memory symbols, uint256 vaultKusdDelta, bool isVaultIncreased
        ['bytes[]', 'bytes[]', 'string[]', 'uint256', 'bool', 'uint256'],
        [messages, signatures, symbols, vaultKusdDelta, isKusdIncreased, new BigNumber(nonce).plus(1)]
        ),
        myPrivateKey);
    messages = signedArr.map(({message}) => message);
    signatures = signedArr.map(({signature}) => signature);

    console.log(messages[0], signatures[0]);

    return kaptain.methods.steer(messages[0], signatures[0]).send({
        from: deployer,
        gasPrice: 10000000000
    }, function (error, transactionHash) {
        if (error) {
            console.error(error);
        } else console.log(transactionHash);
    }).then(function (receipt) {
        console.log(receipt);
    });
}

function encode(kind, timestamp, pairs) {
    const [keyType, valueType] = getKeyAndValueType(kind);
    const [kType, kEnc] = fancyParameterEncoder(keyType);
    const [vType, vEnc] = fancyParameterEncoder(valueType);
    const actualPairs = Array.isArray(pairs) ? pairs : Object.entries(pairs);
    return actualPairs.map(([key, value]) => {
        console.log("key, value", key, value);
        return web3.eth.abi.encodeParameters(['string', 'uint64', kType, vType], [kind, timestamp, kEnc(key), vEnc(value)]);
    });
}

function sign(messages, privateKey) {
    const actualMessages = Array.isArray(messages) ? messages : [messages];
    return actualMessages.map((message) => {
        const hash = web3.utils.keccak256(message);
        const {r, s, v} = web3.eth.accounts.sign(hash, privateKey);
        const signature = web3.eth.abi.encodeParameters(['bytes32', 'bytes32', 'uint8'], [r, s, v]);
        const signatory = web3.eth.accounts.recover(hash, v, r, s);
        return {hash, message, signature, signatory};
    });
}

function getKeyAndValueType(kind) {
    switch (kind) {
        case 'prices':
            return ['symbol', 'decimal'];
        default:
            throw new Error(`Unknown kind of data "${kind}"`);
    }
}

function fancyParameterEncoder(paramType) {
    let actualParamType = paramType, actualParamEnc = (x) => x;

    // We add a decimal type for reporter convenience.
    // Decimals are encoded as uints with 6 decimals of precision on-chain.
    if (paramType === 'decimal') {
        actualParamType = 'uint64';
        actualParamEnc = (x) => web3.utils.toBN(1e6).muln(x).toString();
    }

    if (paramType === 'symbol') {
        actualParamType = 'string';
        actualParamEnc = (x) => x.toUpperCase();
    }

    return [actualParamType, actualParamEnc];
}