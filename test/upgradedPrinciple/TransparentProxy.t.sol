// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console2 } from "forge-std/Test.sol";
import "../../src/upgradedProtocol/TransparentProxy.sol";

contract TransparentProxyTest is Test {
    Storage store;
    LogicV1 logicV1;
    LogicV2 logicV2;
    Proxy proxy;
    address administrator;

    function setUp() public {
        logicV1 = new LogicV1();
        logicV2 = new LogicV2();
        store = new Storage();
        administrator = makeAddr("administrator");

        proxy = new Proxy(address(logicV1), address(store), administrator);
    }

    // 为了防止整形溢出错误，将输入 _a 和 _b 限制为 int128
    function testLogicV1(int128 _a, int128 _b) public {

        (bool success, bytes memory data) = address(proxy).call(
            abi.encodeWithSignature(
                "sum(int256,int256)", 
                _a, 
                _b
            )
        );

        int256 storedResult = store.getResult();
        int256 decodeData = abi.decode(data, (int256));
        int256 calculatedResult = int256(_a) + int256(_b);

        require(success, "call failed");

        assertEq(storedResult, decodeData);
        assertEq(storedResult, calculatedResult);
    }

    // 为了防止整形溢出错误，将输入 _a 和 _b 限制为 int128
    function testLogicV2(int128 _a, int128 _b) public {

        vm.startPrank(administrator);                               // 只有administrator才能升级合约
        proxy.updateLogic(address(logicV2));                        // 升级合约
        vm.stopPrank();                                             // administrator不能直接调用逻辑合约中的函数

        (bool success, bytes memory data) = address(proxy).call(
            abi.encodeWithSignature(
                "sub(int256,int256)",
                _a,
                _b
            )
        );

        int256 storedResult = store.getResult();
        int256 decodeData = abi.decode(data, (int256));
        int256 calculatedResult = int256(_a) - int256(_b);

        require(success, "call failed");

        assertEq(storedResult, decodeData);
        assertEq(storedResult, calculatedResult);
    }
}
