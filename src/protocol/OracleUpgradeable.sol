// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import { ITSwapPool } from "../interfaces/ITSwapPool.sol";
import { IPoolFactory } from "../interfaces/IPoolFactory.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

// notion: upgradeable contract can not have the constructor !!
// proxy contract             -->  storage
// implementation contract    -->  logic
// Initializable contract to do something about storage !!

// 在Solidity中，可升级合约的核心原理是使用代理合约模式（Proxy Pattern），即通过将合约的逻辑与存储分离来实现。
// 这样即使逻辑合约发生变化，存储数据仍然保持不变，从而避免部署新的合约时数据丢失的问题。
// 1. 代理合约：代理合约负责与用户交互，同时转发调用到逻辑合约。它本身并不包含业务逻辑，只包含一个指向逻辑合约地址的存储变量。代理合约使用delegatecall将用户的调用转发给逻辑合约。
// 2. 逻辑合约：逻辑合约包含所有的业务逻辑函数。每次合约升级时，只需部署新的逻辑合约，而无需更改代理合约。代理合约通过存储的地址指向新的逻辑合约。
// 3. 存储数据分离：在使用delegatecall时，逻辑合约的函数在代理合约的上下文中执行，即使用代理合约的存储。这就确保了即使逻辑合约升级，原始的存储状态仍然保持不变。


contract OracleUpgradeable is Initializable {
    address private s_poolFactory;

    // 合约初始化函数，用于设置 s_poolFactory（一个池工厂合约的地址）
    // 只能在合约初始化时调用，且只能在内部使用
    function __Oracle_init(address poolFactoryAddress) internal onlyInitializing {
        __Oracle_init_unchained(poolFactoryAddress);
    }

    // 合约初始化函数
    // 过这种初始化模式（分为 init 和 init_unchained） 
    // 该合约支持可升级特性（基于 OpenZeppelin 的 Initializable 设计模式）
    // the unchained function is used to handle tasks that should be done in the constructor normally.
    function __Oracle_init_unchained(address poolFactoryAddress) internal onlyInitializing {
        s_poolFactory = poolFactoryAddress;
    }

    // 查询某个代币相对于 WETH（Wrapped Ether）的价格
    // IPoolFactory: 提供池子的地址。
    // ITSwapPool: 返回池子的价格信息
    function getPriceInWeth(address token) public view returns (uint256) {
        // 通过 s_poolFactory 访问池工厂合约 (IPoolFactory)
        // 使用池工厂的 getPool(token) 函数获取对应代币的池子合约（swapPoolOfToken）
        
        address swapPoolOfToken = IPoolFactory(s_poolFactory).getPool(token);

        // 调用池子的 getPriceOfOnePoolTokenInWeth 函数，返回代币与 WETH 的价格
        // getOutputAmountBasedOnInput(uint256 inputAmount, uint256 inputReserves, uint256 outputReserves) 
        // getOutputAmountBasedOnInput(1e18, i_poolToken.balanceOf(address(this)), i_weth.balanceOf(address(this)))
        // Δy = y*[Δx/(x + Δx)]      input  -->  output
        return ITSwapPool(swapPoolOfToken).getPriceOfOnePoolTokenInWeth();
    }

    function getPrice(address token) external view returns (uint256) {
        return getPriceInWeth(token);
    }

    function getPoolFactoryAddress() external view returns (address) {
        return s_poolFactory;
    }
}
