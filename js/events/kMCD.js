const {web3} = require("../web3Instance")
const abiJson = require("../../build/contracts/KMCD.json")
const addressObj = require("../../network/ropsten.json")

let kMCD = new web3.eth.Contract(abiJson.abi, addressObj.KMCD.delegator.address);

kMCD.events.allEvents({fromBlock: "latest"})
    .on("connected", function (subscriptionId) {
        console.log("on connected", subscriptionId);
    })
    .on('data', function (event) {
        console.log("on event", event);
    })
    .on('error', function (error, receipt) {
        console.error(error);
    });
