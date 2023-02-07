pragma solidity >= 0.8.0;

import "forge-std/Test.sol";
import {BufferWrapper} from "contracts/adapters/buffer/BufferWrapper.sol";
import {IBufferBinaryPool} from "contracts/interfaces/adapters/misc/IBufferBinaryPool.sol";
import {IERC20} from "contracts/interfaces/IERC20.sol";
import {IERC4626} from "contracts/interfaces/IERC4626.sol";

interface AdminBufferBinaryPool {
        function setMaxLiquidity(uint256 _new) external;
}

/** @author 0xTinder
 *  @notice Tests for Buffer Finance 4626 wrapper
 * 
 */
contract BufferWrapperTest is Test  {
    string ARBITRUM_RPC_URL = vm.envString("ARBITRUM");

    BufferWrapper bufferWrapper;
    IBufferBinaryPool pool = IBufferBinaryPool(0x6Ec7B10bF7331794adAaf235cb47a2A292cD9c7e);

    IERC20 asset;
    IERC4626 adapter;

    address vault;
    address admin = 0xfa1e2DD94D6665bb964192Debac09c16242f8a48;
    address angel = address(1);
    address alice = address(2);
    address bob = address(3);
    uint256 maxLiquidity;
    uint256 maxShares;
    constructor() {
        vm.createSelectFork(ARBITRUM_RPC_URL);

        bufferWrapper = new BufferWrapper(pool);
        bufferWrapper.grantRole('SMART_WALLET', alice);
        bufferWrapper.grantRole('SMART_WALLET', bob);
        bufferWrapper.grantRole('SMART_WALLET', angel);

        hoax(admin, admin);
        ///@dev double max liquidity to test.
        AdminBufferBinaryPool(address(pool)).setMaxLiquidity(3000000000000);
        maxLiquidity = pool.maxLiquidity() - pool.totalTokenXBalance();
        maxShares = (maxLiquidity * pool.totalSupply()) / pool.totalTokenXBalance(); 

        vault = address(bufferWrapper.pool());
        adapter = IERC4626(address(bufferWrapper));
        asset = IERC20(adapter.asset());
        deal(address(asset), angel, type(uint).max);
        startHoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);

        adapter.deposit(1e6, address(0)); // burn first 1000 shares
        // adapter.deposit(10e6, angel);
        vm.stopPrank();

        deal(address(asset), alice, type(uint).max / 2);
        deal(address(asset), bob, type(uint).max / 2);


        vm.label(vault, "BufferBinaryPool");
        vm.label(address(adapter), "BufferWrapper");
        vm.label(address(asset), "USDC");
        vm.label(alice, "alice");
        vm.label(angel, "angel");
        vm.label(bob, "bob");
    }
    /**
     * @notice sanity test
     * Alice deposits USDC, then withdraws it.
     */
    function testSanity() public {
        uint aliceBalance = asset.balanceOf(alice);
        startHoax(alice, alice);
        asset.approve(address(adapter), type(uint).max);
        adapter.deposit(150e6, alice);
        vm.expectRevert(bytes('Pool: Withdrawal amount is greater than current unlocked amount'));
        adapter.withdraw(150e6, alice, alice);
        skip(24 hours);
        console.log(adapter.previewWithdraw(150e6 - 1));
        console.log(adapter.balanceOf(alice));
        adapter.withdraw(150e6 - 1, alice, alice);
        vm.stopPrank();
        assertEq(aliceBalance - 1, asset.balanceOf(alice));
    }
    /**
     * @notice scenario test
     * Alice deposits into wrapper, starting her 1 day lockup timer
     * ~ 12 hours later, Bob deposits in to wrapper
     * ~ 12 hours later, Bob withdraws his funds using the timer started by Alice
     * ~ 12 hours later, Alice withdraws her funds using the timer started by Bob
     */
    function testScenario() public {
        ///@dev This scenario requires a new BufferWrapper or the 10e6 initial deposit
        ///     from angel will throw off the timing mechanics.
        bufferWrapper = new BufferWrapper(pool);
        bufferWrapper.grantRole('SMART_WALLET', alice);
        bufferWrapper.grantRole('SMART_WALLET', bob);
        adapter = IERC4626(address(bufferWrapper));

        uint aliceBalance = asset.balanceOf(alice);
        uint bobBalance = asset.balanceOf(bob);

        startHoax(alice, alice);
        asset.approve(address(adapter), type(uint).max);
        adapter.deposit(0.5e6, alice);
        vm.stopPrank();

        skip(12 hours);

        startHoax(bob, bob);
        asset.approve(address(adapter), type(uint).max);
        adapter.deposit(10e6, bob);
        vm.stopPrank();

        skip(12 hours);

        hoax(bob, bob);
        adapter.withdraw(0.5e6 - 1, bob, bob);

        hoax(alice, alice);
        vm.expectRevert(bytes('Pool: Withdrawal amount is greater than current unlocked amount'));
        adapter.withdraw(0.5e6, alice, alice);

        skip(12 hours);

        hoax(bob, bob);
        vm.expectRevert();
        adapter.withdraw(10e6, bob, bob);

        hoax(alice, alice);
        adapter.withdraw(0.5e6 - 2, alice, alice);
        
        hoax(bob, bob);
        adapter.withdraw(9.5e6 - 1, bob, bob);

        assertEq(aliceBalance - 2, asset.balanceOf(alice));
        assertEq(bobBalance - 2, asset.balanceOf(bob));
    }
    /**
     * @param amount deposit amount 
     * [0, 1e3] -> Revert's Solmate 4626 MIN_DEPOSIT ER043
     * (1e3, maxLiquidity) -> Working range
     * [maxLiquidity, 2**256) -> Buffer Err("Pool has already reached it's max limit")
     * @dev modded at 1e50 to prevent overflow on precondition check
     */

    function testDeposit(uint amount) public virtual {
        amount = amount % 1e50;
        startHoax(alice, alice);
        asset.approve(address(adapter), amount);

        // USDC balances
        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        uint vaultBalance = asset.balanceOf(vault);

        // total supply
        uint adapter_total_supply = adapter.totalSupply();
        uint pool_total_supply = pool.totalSupply();
        IERC20 BLP = IERC20(vault);
        uint pool_shares_owned = BLP.balanceOf(address(adapter));

        uint pool_shares_expected = (amount * pool.totalSupply()) / pool.totalTokenXBalance(); 
        uint adapter_shares_expected = adapter.previewDeposit(amount);
        
        uint adapter_shares_minted;
        if (amount <= 1e3) {
            vm.expectRevert(bytes("ER043"));
            adapter_shares_minted = adapter.deposit(amount, alice);
            return;
        } else if (amount >= maxLiquidity) {
            vm.expectRevert(bytes("Pool has already reached it's max limit"));
            adapter_shares_minted = adapter.deposit(amount, alice);
            return; 
        } else {
            adapter_shares_minted = adapter.deposit(amount, alice);
        }
        
        /**
         *   Alice      4626        Pool
         *   USDC ---->     
         *        <---- Adapter 
         *              Shares
         *              USDC -----> 
         *                   <----- BLP
         */
        // assert USDC balances
        assertEq(asset.balanceOf(alice), aliceBalance - amount, "Alice Balance of Asset did not decrease by desired amount");
        assertEq(asset.balanceOf(address(adapter)), adapterBalance, "Adapter Balance of Asset should not change");
        assertEq(asset.balanceOf(vault), vaultBalance + amount, "Vault USDC balance should have increased by `amount`");

        // assert 4626 shares balances
        assertEq(adapter.balanceOf(alice), adapter_shares_minted, "Alice's 4626 share balance does not match shares minted");
        assertEq(adapter_shares_expected, adapter_shares_minted, "shares expected not matching shares minted to Alice");
        assertEq(adapter.totalSupply(), adapter_total_supply + adapter_shares_minted, "total supply should have increased");

        // assert BLP shares balances
        assertEq(BLP.balanceOf(address(adapter)), pool_shares_owned + pool_shares_expected, "Adapter balance of BLP not equal to expected");
        assertEq(BLP.balanceOf(alice), 0, "Alie should have no BLP");
        assertEq(pool.totalSupply(), pool_total_supply + pool_shares_expected, "total supply should have increased");
    }

    /**
     * @param amount number of shares to mint
     */
    function testMint(uint amount) external virtual {
        amount = amount % 1e50;
        startHoax(alice, alice);
        asset.approve(address(adapter), amount);

        // USDC balances
        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        uint vaultBalance = asset.balanceOf(vault);

        // total supply
        uint adapter_total_supply = adapter.totalSupply();
        uint pool_total_supply = pool.totalSupply();
        IERC20 BLP = IERC20(vault);
        uint pool_shares_owned = BLP.balanceOf(address(adapter));
        uint adapter_assets_expected = adapter.previewMint(amount);
        uint pool_shares_expected = (adapter_assets_expected * pool.totalSupply()) / pool.totalTokenXBalance(); 
        uint adapter_assets_consumed;
        if (adapter_assets_expected <= 1e3) {
            vm.expectRevert(bytes("ER043"));
            adapter_assets_consumed = adapter.mint(amount, alice);
            return;
        } else if (adapter_assets_expected >= maxLiquidity) {
            vm.expectRevert(bytes("Pool has already reached it's max limit"));
            adapter_assets_consumed = adapter.mint(amount, alice);
            return; 
        } else {
            adapter_assets_consumed = adapter.mint(amount, alice);
        }
        /**
         *   Alice      4626        Pool
         *   USDC ---->     
         *        <---- Adapter 
         *              Shares
         *              USDC -----> 
         *                   <----- BLP
         */


        // assert USDC balances
        assertEq(asset.balanceOf(alice), aliceBalance - adapter_assets_consumed, "Alice Balance of Asset did not decrease by desired amount");
        assertEq(asset.balanceOf(address(adapter)), adapterBalance, "Adapter Balance of Asset should not change");
        assertEq(asset.balanceOf(vault), vaultBalance + adapter_assets_consumed, "Vault USDC balance should have increased by `amount`");
        assertEq(adapter_assets_expected, adapter_assets_consumed, "Vault USDC balance should have increased by `amount`");

        // assert 4626 shares balances
        assertEq(adapter.balanceOf(alice), amount, "Alice's 4626 share balance does not match shares minted");
        assertEq(adapter.totalSupply(), adapter_total_supply + amount, "total supply should have increased");

        // assert BLP shares balances
        assertEq(BLP.balanceOf(address(adapter)), pool_shares_owned + pool_shares_expected, "Adapter balance of BLP not equal to expected");
        assertEq(BLP.balanceOf(alice), 0, "Alice should have no BLP");
        assertEq(pool.totalSupply(), pool_total_supply + pool_shares_expected, "total supply should have increased");

    }

    /**
     * @param amount subject to testDeposit restrictions. [1001, maxLiquidity + 1]
     * @param withdrawAmount amount to withdraw
     * [0] -> Buffer ERR("Pool: Amount is too small")
     * [1, poolUSDCBalance] -> working
     * [poolUSDCBalance, 2**256] -> Buffer ERR("Pool: Not enough funds on the pool contract. Please lower the amount.")
     */
    function test_Withdraw(uint amount, uint withdrawAmount) external virtual {
        // apply bounds to amount parameter before calling deposit
        amount = (amount % (maxLiquidity - 1e3)) + 1e3 + 1;
        testDeposit(amount);

        withdrawAmount = withdrawAmount % 1e50;
        if (withdrawAmount == 0) {
            vm.expectRevert(bytes("Pool: Amount is too small"));
            adapter.withdraw(withdrawAmount, alice, alice);
            return;
        } else if (withdrawAmount > pool.totalTokenXBalance()) {
            vm.expectRevert(bytes("Pool: Not enough funds on the pool contract. Please lower the amount."));
            adapter.withdraw(withdrawAmount, alice, alice);
            return;
        } else if (withdrawAmount > amount) {
            vm.expectRevert();
            adapter.withdraw(withdrawAmount, alice, alice);
            return;
        } 

        // USDC balances
        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        uint vaultBalance = asset.balanceOf(vault);

        // total supply
        uint adapter_total_supply = adapter.totalSupply();
        uint pool_total_supply = pool.totalSupply();

        uint adapter_shares_expected = adapter.previewWithdraw(withdrawAmount);
        uint pool_shares_expected = (withdrawAmount * pool.totalSupply()) / pool.totalTokenXBalance(); 
        uint adapter_shares_consumed;

        // 4626 balances
        uint adapter_shares_owned = adapter.balanceOf(alice);

        // lockupperiod = 1 days
        skip(1 days);
        // BLP balances
        IERC20 BLP = IERC20(vault);
        uint pool_shares_owned = BLP.balanceOf(address(adapter));
        if (withdrawAmount > amount) {
            vm.expectRevert(BufferWrapper.InsufficientFundsWithdrawnFromPool.selector);
            adapter.withdraw(withdrawAmount, alice, alice);
            return;
        } else {
            adapter_shares_consumed = adapter.withdraw(withdrawAmount, alice, alice);
        }
        /**
         *   Alice      4626        Pool
         *   USDC ---->     
         *        <---- Adapter 
         *              Shares
         *              USDC -----> 
         *                   <----- BLP
         */


        // assert USDC balances
        assertEq(asset.balanceOf(alice), aliceBalance + withdrawAmount, "Alice Balance of Asset did not decrease by desired amount");
        assertEq(asset.balanceOf(address(adapter)), adapterBalance, "Adapter Balance of Asset should not change");
        assertEq(asset.balanceOf(vault), vaultBalance - withdrawAmount, "Vault USDC balance should have increased by `amount`");

        // assert 4626 shares balances
        assertEq(adapter.balanceOf(alice), adapter_shares_owned - adapter_shares_consumed, "Alice's 4626 share balance does not match shares minted");
        assertEq(adapter.totalSupply(), adapter_total_supply - adapter_shares_consumed, "total supply should have increased");
        assertEq(adapter_shares_expected, adapter_shares_consumed, "Vault USDC balance should have increased by `amount`");

        // assert BLP shares balances
        assertEq(BLP.balanceOf(address(adapter)), pool_shares_owned - pool_shares_expected - 1, "Adapter balance of BLP not equal to expected");
        assertEq(BLP.balanceOf(alice), 0, "Alice should have no BLP");
        assertEq(pool.totalSupply(), pool_total_supply - pool_shares_expected - 1, "total supply should have increased");

    }
    /**
     * @param amount subject to testDeposit restrictions. [1001, maxLiquidity + 1]
     * @param redeemAmount amount to redeem
     * [0] -> Solmat 4626 ERR("ZERO_ASSETS")
     * [1, poolUSDCBalance] -> working
     * [poolUSDCBalance, 2**256] -> Buffer ERR("Pool: Not enough funds on the pool contract. Please lower the amount.")
     */
    function test_Redeem(uint256 amount, uint256 redeemAmount) external virtual {
        // apply bounds to amount parameter before calling deposit
        amount = (amount % (maxLiquidity - 1e3)) + 1e3 + 1;
        testDeposit(amount);

        redeemAmount = redeemAmount % 1e50;

        // USDC balances
        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        uint vaultBalance = asset.balanceOf(vault);

        // total supply
        uint adapter_total_supply = adapter.totalSupply();
        uint pool_total_supply = pool.totalSupply();

        uint adapter_assets_expected = adapter.previewRedeem(redeemAmount);
        uint pool_shares_expected = (adapter_assets_expected * pool.totalSupply()) / pool.totalTokenXBalance(); 
        uint adapter_assets_received;

        if (adapter_assets_expected == 0) {
            vm.expectRevert(bytes("ZERO_ASSETS"));
            adapter.redeem(redeemAmount, alice, alice);
            return;
        } else if (adapter_assets_expected > pool.totalTokenXBalance()) {
            vm.expectRevert(bytes("Pool: Not enough funds on the pool contract. Please lower the amount."));
            adapter.redeem(redeemAmount, alice, alice);
            return;
        }

        // 4626 balances
        uint adapter_shares_owned = adapter.balanceOf(alice);

        // lockupperiod = 1 days
        skip(1 days);
        // BLP balances
        IERC20 BLP = IERC20(vault);
        uint pool_shares_owned = BLP.balanceOf(address(adapter));
        if (redeemAmount > adapter_shares_owned) {
            vm.expectRevert();
            adapter.withdraw(redeemAmount, alice, alice);
            return;
        } else {
            adapter_assets_received = adapter.redeem(redeemAmount, alice, alice);
        }
        /**
         *   Alice      4626        Pool
         *   USDC ---->     
         *        <---- Adapter 
         *              Shares
         *              USDC -----> 
         *                   <----- BLP
         */


        // assert USDC balances
        assertEq(asset.balanceOf(alice), aliceBalance + adapter_assets_received, "Alice Balance of Asset did not decrease by desired amount");
        assertEq(asset.balanceOf(address(adapter)), adapterBalance, "Adapter Balance of Asset should not change");
        assertEq(asset.balanceOf(vault), vaultBalance - adapter_assets_received, "Vault USDC balance should have increased by `amount`");
        assertEq(adapter_assets_expected, adapter_assets_received, "USDC received doesn't match expected");

        // assert 4626 shares balances
        assertEq(adapter.balanceOf(alice), adapter_shares_owned - redeemAmount, "Alice's 4626 share balance does not match shares minted");
        assertEq(adapter.totalSupply(), adapter_total_supply - redeemAmount, "total supply should have increased");

        // assert BLP shares balances
        assertEq(BLP.balanceOf(address(adapter)), pool_shares_owned - pool_shares_expected - 1, "Adapter balance of BLP not equal to expected");
        assertEq(BLP.balanceOf(alice), 0, "Alice should have no BLP");
        assertEq(pool.totalSupply(), pool_total_supply - pool_shares_expected - 1, "total supply should have decreased");
    }
    function test_DepositWithdrawRoundtrip() external {
        uint amount = 1e6;
        uint usdcBalance = asset.balanceOf(alice);
        startHoax(alice, alice);
        asset.approve(address(adapter), amount);
        adapter.deposit(amount, alice);
        skip(1 days);
        adapter.withdraw(amount - 1, alice, alice);
        assertEq(usdcBalance - 1, asset.balanceOf(alice));
    }

}