// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { BaseTest } from "./BaseTest.t.sol";

// 继承自 BaseTest，意味着 setUp() 中定义的初始化逻辑会在每次运行测试之前执行。
// 包括 ThunderLoan 的初始化、模拟的 ERC20Mock 代币的部署，以及通过 MockPoolFactory 创建的流动性池

contract OracleUpgradeableTest is BaseTest {
    function testInitializationOracle() public {
        assertEq(thunderLoan.getPoolFactoryAddress(), address(mockPoolFactory));
    }


    function testGetPrice() public {
        assertEq(thunderLoan.getPrice(address(tokenA)), 1e18);
    }
}
