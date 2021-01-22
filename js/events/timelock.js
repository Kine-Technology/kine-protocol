const {web3} = require("../web3Instance")
const abiJson = require("../../build/contracts/Timelock.json")
const addressObj = require("../../network/ropsten-uat.json")

let contract = new web3.eth.Contract(abiJson.abi, addressObj.timelock_test.address);

contract.events.allEvents({fromBlock: "latest"})
    .on("connected", function (subscriptionId) {
        console.log("on connected", subscriptionId);
    })
    .on('data', function (event) {
        console.log("on event", event);
    })
    .on('error', function (error, receipt) {
        console.error(error);
    });
