import hre, { ethers } from "hardhat";
import lzChainIds from "./constants/lzChainIds.json";
import polygonMumbaiAddresses from "../../deploy/addresses/polygonMumbai.json";
import scrollSepoliaAddresses from "../../deploy/addresses/scrollSepolia.json";

async function main() {
    let [signer] = await ethers.getSigners();
    const chainId = await signer.getChainId();
    let contractAddress, dstChainId, sendRelayer, receiveRelayer;
    switch (chainId) {
        case 80001: {
            contractAddress = polygonMumbaiAddresses["versaOmniFactory"];
            dstChainId = lzChainIds["scroll-sepolia"];
            sendRelayer = "0x038b6098dA32957f2EbBF6dc743F0DC6810ac8C7";
            receiveRelayer = "0x038b6098dA32957f2EbBF6dc743F0DC6810ac8C7";
            break;
        }
        case 534351: {
            contractAddress = scrollSepoliaAddresses["versaOmniFactory"];
            dstChainId = lzChainIds["polygon-mumbai"];
            sendRelayer = "0xb23b28012ee92E8dE39DEb57Af31722223034747";
            receiveRelayer = "0xb23b28012ee92E8dE39DEb57Af31722223034747";
            break;
        }
        default: {
            console.log("unsupported network");
        }
    }
    const contractInstance = await ethers.getContractAt("VersaOmniFactory", contractAddress);
    console.log(`[${hre.network.name}] VersaOmniFactory Address: ${contractAddress}`);
    const tx = await (await contractInstance.setRelayer(dstChainId, sendRelayer, receiveRelayer)).wait();
    console.log(`✅ Set Relayer: [${sendRelayer}][${receiveRelayer}] for src (${chainId}) -> dst (${dstChainId})`);
    console.log(`txhash: ${tx.transactionHash}`);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
