// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import "../../src/upgradedProtocol/DelegateCall.sol";

contract DelegateCallTest is Test {
    Target target;
    Caller caller;

    function setUp() public {
        target = new Target();
        caller = new Caller(address(target));
    }

    function testCall(uint256 _num, address _addr) public {
        caller.callSetVariables(_num, _addr);                   // 使用 call 方式调用，会修改 Target 合约中的变量
        (uint256 num, address addr) = target.getVariables();    // 获取 Target 合约中的状态
        assertEq(num, _num);
        assertEq(addr, _addr);
    }

    function testDelegatecall(uint256 _num, address _addr) public {
        caller.delegateCallSetVariables(_num, _addr);           // 使用 delegatecall 方式调用，会修改 Caller 合约中的变量，也就是改变了自身的变量
        (uint256 num, address addr) = caller.getVariables();    // 获取 Caller 合约中的状态
        assertEq(num, _num);
        assertEq(addr, _addr);
    }
}