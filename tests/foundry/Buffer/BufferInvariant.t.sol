pragma solidity 0.8.17;

import "forge-std/Test.sol";
import "forge-std/InvariantTest.sol";
import {BufferWrapper} from "contracts/adapters/buffer/BufferWrapper.sol";
import {IERC4626} from "contracts/interfaces/IERC4626.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IBufferBinaryPool} from "contracts/interfaces/adapters/misc/IBufferBinaryPool.sol";

interface AdminBufferBinaryPool {
        function setMaxLiquidity(uint256 _new) external;
}


contract BufferInvariantTest is Test, InvariantTest {
    IERC4626 public wrapper;
    IBufferBinaryPool pool = IBufferBinaryPool(0x6Ec7B10bF7331794adAaf235cb47a2A292cD9c7e);

    uint256 initUSDCBalance;
    IERC20 USDC = IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);

    address admin = 0xfa1e2DD94D6665bb964192Debac09c16242f8a48;
    
    //Access variables from .env file via vm.envString("varname")
    //Replace ALCHEMY_KEY by your alchemy key or Etherscan key, change RPC url if need
    //inside your .env file e.g: 
    //  MAINNET_RPC_URL = 'https://eth-mainnet.g.alchemy.com/v2/ALCHEMY_KEY'
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM");
    //string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");
    
    function setUp() public {
        vm.createSelectFork(ARBITRUM_RPC_URL);
        wrapper = IERC4626(address(new BufferWrapper(pool))); // deploy example contract
        targetContract(address(wrapper)); // target "StorageInvariant"

        hoax(admin, admin);
        AdminBufferBinaryPool(address(pool)).setMaxLiquidity(1000000000000);

        initUSDCBalance = USDC.balanceOf(address(wrapper));
    }

    /// @notice Since the adapter should always pass USDC onto the pool contract,
    /// its usdc balance should never change.
    function invariantTestStore() public {
        assertEq(USDC.balanceOf(address(wrapper)), initUSDCBalance);
    }
}