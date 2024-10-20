// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";

import {Protocol} from "src/realLend/Protocol.sol";
import {USDC} from "src/USDC.sol";
import {Cottage} from "src/realLend/Cottage.sol";

/// @notice A very simple deployment script
contract Deploy is Script {
    /// @notice The main script entrypoint
    /// @return protocol The deployed contract
    function run() external returns (Protocol protocol, USDC usdc, Cottage cottage) {
        vm.startBroadcast();
        protocol = new Protocol();
        usdc = new USDC();
        cottage = new Cottage();
        vm.stopBroadcast();
    }
}
