const {web3} = require("../web3Instance")
const abiJson = require("../../build/contracts/KineUSD.json")
const addressObj = require("../../network/ropsten.json")

let kUSD = new web3.eth.Contract(abiJson.abi, addressObj.KineUSD.address);

kUSD.events.allEvents({fromBlock: "latest"})
    .on("connected", function (subscriptionId) {
        console.log("on connected", subscriptionId);
    })
    .on('data', function (event) {
        console.log("on event", event);
    })
    .on('error', function (error, receipt) {
        console.error(error);
    });
