// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { ThunderLoan } from "../../src/protocol/ThunderLoan.sol";
import { ERC20Mock } from "../mocks/ERC20Mock.sol";
import { MockTSwapPool } from "../mocks/MockTSwapPool.sol";
import { MockPoolFactory } from "../mocks/MockPoolFactory.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BaseTest is Test {
    ThunderLoan thunderLoanImplementation;
    MockPoolFactory mockPoolFactory;
    ERC1967Proxy proxy;                  // 可升级代理合约，通过代理指向 ThunderLoan 实现    proxy --> thunderLoan
    ThunderLoan thunderLoan;

    address thunderLoanOwner = makeAddr("thunderLoanOwner");

    ERC20Mock weth;
    ERC20Mock tokenA;

    function setUp() public virtual {
        // 注意：thunderLoad 设置 owner 是在 initialize 函数中进行的
        // 此时 thunderLoan.owner() = address(0)
        // ThunderLoan 实现合约被实例化，但只是作为实现合约使用，不直接调用，通过 proxy 合约调用
        thunderLoan = new ThunderLoan();            

        mockPoolFactory = new MockPoolFactory();

        weth = new ERC20Mock();
        tokenA = new ERC20Mock();

        mockPoolFactory.createPool(address(tokenA));            // 创建一个与 tokenA 关联的模拟流动性池
        proxy = new ERC1967Proxy(address(thunderLoan), "");     // 使用 ERC1967Proxy 部署一个可升级代理，将 ThunderLoan 实现合约的地址传递给代理
        
        thunderLoan = ThunderLoan(address(proxy));

        // 注意：thunderLoad 设置 owner 是在 initialize 函数中进行的
        vm.prank(thunderLoanOwner);
        thunderLoan.initialize(address(mockPoolFactory));

    }
}
