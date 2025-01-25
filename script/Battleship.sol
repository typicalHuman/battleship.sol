// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Battleship} from "../src/Battleship.sol";

contract BattleshipScript is Script {
    Battleship public battleship;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        address usdcToken = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // on base
        battleship = new Battleship(usdcToken, 50e6); // 50$ safe deposit
        vm.stopBroadcast();
    }
}
