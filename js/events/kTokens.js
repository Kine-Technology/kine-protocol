const {web3} = require("../web3Instance")
const kEthAbiJson = require("../../build/contracts/KEther.json")
const kErc20AbiJson = require("../../build/contracts/KErc20.json")
const addressObj = require("../../network/ropsten.json")

let kEther = new web3.eth.Contract(kEthAbiJson.abi, addressObj.KTokens.kETH.address);

kEther.events.allEvents({fromBlock: "latest"})
    .on("connected", function (subscriptionId) {
        console.log("on connected", subscriptionId);
    })
    .on('data', function (event) {
        console.log("on event", event);
    })
    .on('error', function (error, receipt) {
        console.error(error);
    });

let kUSDC = new web3.eth.Contract(kErc20AbiJson.abi, addressObj.KTokens.kUSDC.delegator.address);

kUSDC.events.allEvents({fromBlock: "latest"})
    .on("connected", function (subscriptionId) {
        console.log("on connected", subscriptionId);
    })
    .on('data', function (event) {
        console.log("on event", event);
    })
    .on('error', function (error, receipt) {
        console.error(error);
    });