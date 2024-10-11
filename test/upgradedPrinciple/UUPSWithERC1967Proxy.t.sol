// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../src/upgradedProtocol/UUPSWithERC1967Proxy.sol";

contract UUPSTest is Test {
    Storage storageContract;
    LogicV1 logicV1;
    LogicV2 logicV2;
    ERC1967Proxy proxy;
    address owner = makeAddr("owner");

    function setUp() public {
        vm.startPrank(owner);

        storageContract = new Storage();                                            // 部署存储合约
        logicV1 = new LogicV1();                                                    // 部署逻辑合约V1
        
        // 部署代理合约，将逻辑合约V1的地址作为初始实现合约地址
        // 注意：这里已经调用 initialize 函数了
        bytes memory data = abi.encodeWithSelector(
            logicV1.initialize.selector, 
            address(storageContract)
        ); 

        proxy = new ERC1967Proxy(address(logicV1), data);                           

        LogicV1(address(proxy)).transferOwnership(owner);                           // 显式将代理合约的所有权转移给 owner

        // LogicV1(address(proxy)).initialize();                                    // 由于上面已经调用了 initialize的逻辑了，因此不需要再初始化代理了
        
        // 如果在 setUp 中没有调用 vm.stopPrank();，
        // 那么在后续执行的测试函数中，所有操作都将以 owner 的身份运行
        vm.stopPrank();                                                       
    }

    function testLogicV1Sum(int128 _a, int128 _b) public {
        
        int calculatedResult = LogicV1(address(proxy)).sum(_a, _b);                 // 测试代理合约指向 LogicV1，调用 sum 方法

        int storedResult = storageContract.getResult();

        assertEq(calculatedResult, storedResult);
    }

    function testUpgradeToLogicV2(int128 _a, int128 _b) public {
        vm.startPrank(owner);
        
        logicV2 = new LogicV2();                                                    // 部署逻辑合约 LogicV2

        // LogicV1(address(proxy)).transferOwnership(address(this));                   // 转移所有权到测试合约

        // 升级到 LogicV2 版本
        // 一定注意：在 OpenZeppelin 5.0.0 中，UUPSUpgradeable 合约不再包含 upgradeTo 方法，只有 upgradeToAndCall 方法
        LogicV1(address(proxy)).upgradeToAndCall(address(logicV2), "");             

        int calculatedResult = LogicV2(address(proxy)).sub(_a, _b);                 // 测试代理合约指向 LogicV2，调用 sub 方法
        int storedResult = storageContract.getResult();

        assertEq(calculatedResult, storedResult);

        vm.stopPrank();
    }
}