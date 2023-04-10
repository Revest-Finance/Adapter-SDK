pragma solidity >= 0.8.0;

import "forge-std/Test.sol";
import "../GenericAdapter.t.sol";
import "contracts/adapters/gmd/GmdBfrAdapter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface BufferBinaryPool {
    function setMaxLiquidity(uint256 _maxLiquidity) external;
}

interface gmdBFRPool {
    function setPoolCap(uint256, uint256) external;
}

contract gmdBfrAdapterTest is GenericAdapter, Test  {
    GmdBfrAdapter GMDAdapter;

    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address GMDvault = 0x56009e94418ddFE8604331ECEFf38db0738775f8;
    address gBfrUSDC = 0xD706A8A16E71E40f791169715A94CEC1f89B08eF;

    address bufferPool = 0x6Ec7B10bF7331794adAaf235cb47a2A292cD9c7e;

    // REFERENCE => Confidence Interval = 0.001e18 = 0.1%
    ERC20 asset;
    ERC4626 adapter;

    uint PID = 0;

    address vault;

    address angel = address(1);
    address alice = address(2);
    address bob = address(3);
    uint256 tolerance = 10;

   
    constructor() {
        GMDAdapter = new GmdBfrAdapter(USDC, GMDvault, gBfrUSDC, PID);

        vault = address(GMDAdapter.vault());

        adapter = ERC4626(address(GMDAdapter));
        asset = adapter.asset();
        deal(address(asset), angel, 1e16);
        hoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);
        deal(address(asset), alice, 1e16);


        hoax(Ownable(bufferPool).owner());
        BufferBinaryPool(bufferPool).setMaxLiquidity(1e50);
        hoax(Ownable(GMDvault).owner());
        gmdBFRPool(GMDvault).setPoolCap(PID, 1e50);

        vm.label(vault, "vault");
        vm.label(address(adapter), "adapter");
        vm.label(address(asset), "asset");
        vm.label(alice, "alice");
        vm.label(angel, "angel");
        vm.label(bob, "bob");

        uint random = 1e6;
        startHoax(angel, angel);
        adapter.deposit(random, angel);
        // adapter.deposit(random / 2 * 1e18, angel);
        // adapter.deposit(random * 1e18, angel);
        vm.stopPrank();
    }

    function testSetup() external virtual {

    }

    function testDeposit(uint amount) external virtual {
        vm.assume(amount < 1e12 && amount > 1e6);

        startHoax(alice, alice);
        asset.approve(address(adapter), amount);

        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        uint vaultBalance = asset.balanceOf(vault);

        uint preview = adapter.previewDeposit(amount);

        console.log("Pre balance: ", IERC20(gBfrUSDC).balanceOf(address(adapter)));

        uint shares_minted = adapter.deposit(amount, alice);

        assertEq(asset.balanceOf(alice), aliceBalance - amount, "Alice Balance of Asset did not decrease by desired amount");
        assertGt(adapter.balanceOf(alice), 0, "Alice Balance should not be zero");

        // assertEq(adapter.balanceOf(alice), shares_minted, "Alice's Share balance does not match shares minted");
        // console.log("balance adapter: ", IERC20(vault).balanceOf(address(BeefyAdapter)));

        // assertGt(IERC20(vault).balanceOf(address(BeefyAdapter)), 0, "Adapter Share balance should not be zero");
        assertEq(asset.balanceOf(address(vault)), vaultBalance, "Vault Appreciated, it shouldn't have");
        assertGt(IERC20(gBfrUSDC).balanceOf(address(adapter)), 0, "Adapter Share Balance should not be zero");
        assertApproxEqAbs(preview, shares_minted, tolerance, "shares expected not matching shares minted to Alice");

        assertGe(shares_minted, preview, "deposit NOT >= previewDeposit");
    }

    //test the mint function - Just mint some amount of tokens
    function testMint(uint amount) external virtual {
        vm.assume(amount < 1e12 && amount > 1e6); //picks some amount of tokens

        startHoax(alice, alice);

        uint preview = adapter.previewDeposit(amount); //how many shares can you get for amount
        asset.approve(address(adapter), type(uint).max); //approve 

        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        
        uint previewMint = adapter.previewMint(preview);
        uint mint = adapter.mint(preview, alice); //returns number of assets used to mint preview-shares

        assertEq(asset.balanceOf(alice), aliceBalance - mint, "Alice's Asset balance did not decrease correctly");
        assertGt(IERC20(gBfrUSDC).balanceOf(address(adapter)), 0, "Adapter Share Balance should not be zero");
        assertApproxEqRel(amount, mint, 0.001e18, "Amount quoted does not match amount minted"); //Within .01% accuracy

        assertLe(mint, previewMint, "previewMint NOT >= mint");

    }

    //Test a deposit and withdraw some amount less than deposit
    function testWithdraw(uint amount, uint withdrawAmount) external virtual {
        vm.assume(amount < 1e12 && amount > 1e6);
        amount = bound(amount, 1e6, 1e12);
        vm.assume(withdrawAmount < amount && withdrawAmount >= 1e3);

        startHoax(alice, alice);

        asset.approve(address(adapter), amount);
        uint shares_received = adapter.deposit(amount, alice);

        skip(1 days);

        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = IERC20(gBfrUSDC).balanceOf(address(adapter));

        uint preview = adapter.previewWithdraw(withdrawAmount);

        // console2.log("preview: ", preview);
        // console2.log("alice shares: ", adapter.balanceOf(alice));

        
        uint shares_burnt = adapter.withdraw(withdrawAmount, alice, alice);
        assertApproxEqAbs(asset.balanceOf(alice), aliceBalance + withdrawAmount, tolerance, "Tokens not returned to alice from withdrawal");
        assertLt(IERC20(gBfrUSDC).balanceOf(address(adapter)), adapterBalance, "Adapter Balance did not decrease");
        assertLe(shares_burnt, preview, "Shares actually burned should be <= previewWithdraw");
    }

    function testRedeem(uint256 amount, uint256 redeemAmount) external virtual {
        vm.assume(amount < 1e12 && amount > 1e6);
        vm.assume(redeemAmount <= amount && redeemAmount >= 1e6);

        startHoax(alice, alice);

        asset.approve(address(adapter), type(uint).max);
        uint shares_received = adapter.mint(amount, alice);

        skip(1 days);

        uint aliceTokenBalance = asset.balanceOf(alice);
        uint aliceAdapterBalance = adapter.balanceOf(alice);
        uint adapterBalance = IERC20(gBfrUSDC).balanceOf(address(adapter));

        uint previewRedeem = adapter.previewRedeem(redeemAmount);
        uint redeem = adapter.redeem(redeemAmount, alice, alice);

        assertGe(redeem, previewRedeem, 'Redeem >= previewRedeem ERC4626');

        assertEq(asset.balanceOf(alice), aliceTokenBalance + previewRedeem, "Correct amount of tokens not returned to alice");

        assertLt(IERC20(gBfrUSDC).balanceOf(address(adapter)), adapterBalance, "Adapter Balance did not decrease");
        assertLt(adapter.balanceOf(alice), aliceAdapterBalance, "Alice's share balance did not decrease");
        assertEq(asset.balanceOf(alice), aliceTokenBalance + previewRedeem, "Alice Token Balance Did not increase correctly");
        assertEq(previewRedeem, redeem, "Shares redeemed does not equal shares quotes to be redeemed");

    }

    // Round trips
    function testRoundTrip_deposit_withdraw(uint amount) external virtual {
        // Deposit
        vm.assume(amount < 1e9 && amount > 1e6);

        startHoax(alice, alice);
        asset.approve(address(adapter), type(uint).max);
        uint initAliceBalance = asset.balanceOf(alice);
        uint initadapterBalance = asset.balanceOf(address(adapter));

        uint previewDeposit = adapter.previewDeposit(amount);
        uint deposit = adapter.deposit(amount, alice);
        
        skip(1 days);

        assertApproxEqAbs(asset.balanceOf(alice), initAliceBalance - amount, tolerance, "improper amount decreased from alice's address");
        // assertEq(asset.balanceOf(address(adapter)), initadapterBalance + amount, "");
        assertGt(IERC20(gBfrUSDC).balanceOf(address(adapter)), 0, "Adapter share balance shouldn't be zero");
        assertEq(adapter.balanceOf(alice), previewDeposit, "Alice share value does not match quoted amount");
        assertEq(previewDeposit, deposit, "amount quoted to mint not matching actually minted amount");
        
        // Withdraw
        uint vaultPreBalance = IERC20(gBfrUSDC).balanceOf(address(adapter));

        uint maxWithdraw = adapter.maxWithdraw(alice);

        uint previewWithdraw = adapter.previewWithdraw(maxWithdraw);

        uint shares_burnt = adapter.withdraw(maxWithdraw, alice, alice);

        assertGe(asset.balanceOf(alice), initAliceBalance, "alice balance not within reliable range at the end of test");
        // assertEq(asset.balanceOf(address(adapter)), initadapterBalance, "adapter balance is not same at end of test");
        assertEq(previewWithdraw, shares_burnt, "shares burnt does not match quoted burn amount");
        assertLt(IERC20(gBfrUSDC).balanceOf(address(adapter)), vaultPreBalance, "Adapter share balance did not decrease");
    }

    function testRoundTrip_mint_redeem(uint amount) external virtual {
        // Mint
        vm.assume(amount < 1e9 && amount > 1e6);

        startHoax(alice, alice);
        asset.approve(address(adapter), type(uint).max);
        uint initAliceBalance = asset.balanceOf(alice);
        uint initadapterBalance = asset.balanceOf(address(adapter));

        uint previewMint = adapter.previewMint(amount);
        uint mint = adapter.mint(amount, alice);

        skip(1 days);

        assertEq(asset.balanceOf(alice), initAliceBalance - previewMint, "Alice's token balance not decreased by proper amount");
        assertGt(IERC20(gBfrUSDC).balanceOf(address(adapter)), 0, "Adapter share balance shouldn't be zero");
        assertGt(adapter.balanceOf(alice), 0, "Alice Share value should not be zero");
        assertEq(previewMint, mint, "assets quoted to be transferred not matching actual amount");

        // Redeem
        uint previewRedeem = adapter.previewRedeem(mint);
        uint assets_converted = adapter.redeem(mint, alice, alice);

        assertGe(asset.balanceOf(alice), initAliceBalance, "alice balance not within reliable range at the end of test");
        assertGe(assets_converted, previewRedeem, "redeem NOT >= previewRedeem");
        assertEq(previewRedeem, assets_converted, "assets actually transferred to burn not same as quoted amount");
    }

    function testMiscViewMethods(uint amount) external virtual {
        uint maxDeposit = adapter.maxDeposit(alice);
        uint maxMint = adapter.maxMint(alice);

        uint maxWithdraw = adapter.maxWithdraw(angel);
        uint maxRedeem = adapter.maxWithdraw(angel);

        assertGt(maxDeposit, 0, "maxDeposit should not be zero");
        assertGt(maxRedeem, 0, "maxRedeem should not be zero");
        assertGt(maxMint, 0, "maxMint should not be zero");
        assertGt(maxWithdraw, 0, "maxWithdraw should not be zero");
    }

}