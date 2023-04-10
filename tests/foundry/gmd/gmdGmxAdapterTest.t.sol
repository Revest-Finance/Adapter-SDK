pragma solidity >= 0.8.0;

import "forge-std/Test.sol";
import "../GenericAdapter.t.sol";
import "contracts/adapters/gmd/GmdGmxAdapter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract gmdGmxAdapterTest is GenericAdapter, Test  {
    // string ARBITRUM_RPC_URL = vm.envString("ARBITRUM");

    GmdGmxAdapter GMDAdapter;

    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address GMDvault = 0x8080B5cE6dfb49a6B86370d6982B3e2A86FBBb08;
    address gmdUSDC = 0x3DB4B7DA67dd5aF61Cb9b3C70501B1BdB24b2C22;

    uint usdcPID = 0;

    // REFERENCE => Confidence Interval = 0.001e18 = 0.1%
    ERC20 asset;
    ERC4626 adapter;

    address vault;

    address angel = address(1);
    address alice = address(2);
    address bob = address(3);
    uint256 tolerance = 10;

    bytes32 public constant SMART_WALLET = 'SMART_WALLET';
   
    constructor() {
        GMDAdapter = new GmdGmxAdapter(USDC, GMDvault, gmdUSDC, usdcPID);

        GMDAdapter.grantRole(SMART_WALLET, alice);
        GMDAdapter.grantRole(SMART_WALLET, angel); 
        GMDAdapter.grantRole(SMART_WALLET, bob);        

        vault = address(GMDAdapter.vault());

        adapter = ERC4626(address(GMDAdapter));
        asset = adapter.asset();
        deal(address(asset), angel, type(uint).max);
        hoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);
        deal(address(asset), alice, type(uint).max / 2);

        vm.label(vault, "vault");
        vm.label(address(adapter), "adapter");
        vm.label(address(asset), "asset");
        vm.label(alice, "alice");
        vm.label(angel, "angel");
        vm.label(bob, "bob");

        //Raise the cap for testing purposes
        address owner = Ownable(GMDvault).owner();
        hoax(owner, owner);
        IGMDVault(GMDvault).setPoolCap(usdcPID, 1e50);

        uint random = 1e6;
        startHoax(angel, angel);
        adapter.deposit(random, angel);

        assertEq(adapter.balanceOf(angel), 1e6 * 0.995e6 / 1e6);

        assertGt(ERC20(gmdUSDC).balanceOf(address(adapter)), 0, "balance of gmdUSDC = 0");
        vm.stopPrank();
    }

    function testSetup() external {

    }

    function testDeposit(uint amount) external virtual {
        vm.assume(amount < 1e9 && amount > 1e6);

        startHoax(alice, alice);
        asset.approve(address(adapter), amount);

        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        uint vaultBalance = asset.balanceOf(vault);

        uint preview = adapter.previewDeposit(amount);

        assertGt(preview, 0, "preview deposit == 0");

        uint shares_minted = adapter.deposit(amount, alice);

        assertEq(asset.balanceOf(alice), aliceBalance - amount, "Alice Balance of Asset did not decrease by desired amount");
        assertGt(adapter.balanceOf(alice), 0, "Alice Balance should not be zero");

        assertEq(adapter.balanceOf(alice), shares_minted, "Alice's Share balance does not match shares minted");
        // console.log("balance adapter: ", IERC20(vault).balanceOf(address(BeefyAdapter)));

        assertEq(asset.balanceOf(address(vault)), vaultBalance, "Vault Appreciated, it shouldn't have");
        assertGt(IERC20(gmdUSDC).balanceOf(address(adapter)), 0, "Adapter Share Balance should not be zero");
        assertApproxEqAbs(preview, shares_minted, tolerance, "shares expected not matching shares minted to Alice");

        assertGe(shares_minted, preview, "deposit NOT >= previewDeposit");
    }

    //test the mint function - Just mint some amount of tokens
    function testMint(uint amount) external virtual {
        vm.assume(amount < 1e9 && amount > 1e6); //picks some amount of tokens

        startHoax(alice, alice);

        uint preview = adapter.previewDeposit(amount); //how many shares can you get for amount
        asset.approve(address(adapter), type(uint).max); //approve 

        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        
        uint previewMint = adapter.previewMint(preview);
        uint mint = adapter.mint(preview, alice); //returns number of assets used to mint preview-shares

        assertEq(asset.balanceOf(alice), aliceBalance - mint, "Alice's Asset balance did not decrease correctly");
        assertGt(IERC20(gmdUSDC).balanceOf(address(adapter)), 0, "Adapter Share Balance should not be zero");
        assertApproxEqRel(amount, mint, 0.001e18, "Amount quoted does not match amount minted"); //Within .01% accuracy

        assertLe(mint, previewMint, "previewMint NOT >= mint");

    }

    //Test a deposit and withdraw some amount less than deposit
    function testWithdraw(uint amount, uint withdrawAmount) external virtual {
        // vm.assume(amount < 1e50 && amount > 1e18);
        amount = bound(amount, 1e9, 1e12);

        //GMX takes a 0.5% deposit fee, thus the /2 to prevent the bounds checker from erroring
        vm.assume(withdrawAmount < amount / 2 && withdrawAmount >= 1e3);
     
        startHoax(alice, alice);

        asset.approve(address(adapter), amount);
        uint shares_received = adapter.deposit(amount, alice);

        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = IERC20(gmdUSDC).balanceOf(address(adapter));

        uint preview = adapter.previewWithdraw(withdrawAmount);

        console2.log("preview: ", preview);
        console2.log("alice shares: ", adapter.balanceOf(alice));

        console.log("amount: ", amount);
        console.log("withdraw amount: ", withdrawAmount);

        uint shares_burnt = adapter.withdraw(withdrawAmount, alice, alice);

        assertApproxEqAbs(asset.balanceOf(alice), aliceBalance + withdrawAmount, tolerance, "Tokens not returned to alice from withdrawal");
        assertLt(IERC20(gmdUSDC).balanceOf(address(adapter)), adapterBalance, "Adapter Balance did not decrease");
        assertLe(shares_burnt, preview, "Shares actually burned should be <= previewWithdraw");
    }

    function testRedeem(uint256 amount, uint256 redeemAmount) external virtual {
        vm.assume(amount < 1e10 && amount > 1e6);
        vm.assume(redeemAmount <= amount && redeemAmount >= 1e6);

        startHoax(alice, alice);

        asset.approve(address(adapter), type(uint).max);
        uint shares_received = adapter.mint(amount, alice);

        uint aliceTokenBalance = asset.balanceOf(alice);
        uint aliceAdapterBalance = adapter.balanceOf(alice);
        uint adapterBalance = IERC20(gmdUSDC).balanceOf(address(adapter));

        uint previewRedeem = adapter.previewRedeem(redeemAmount);
        uint redeem = adapter.redeem(redeemAmount, alice, alice);

        assertGe(redeem, previewRedeem, 'Redeem >= previewRedeem ERC4626');

        assertGe(asset.balanceOf(alice), aliceTokenBalance + previewRedeem, "Correct amount of tokens not returned to alice");

        assertLt(IERC20(gmdUSDC).balanceOf(address(adapter)), adapterBalance, "Adapter Balance did not decrease");
        assertLt(adapter.balanceOf(alice), aliceAdapterBalance, "Alice's share balance did not decrease");
        assertGe(asset.balanceOf(alice), aliceTokenBalance + previewRedeem, "Alice Token Balance Did not increase correctly");
        assertGe(redeem, previewRedeem, "Shares redeemed does not equal shares quotes to be redeemed");

    }

    // Round trips
    function testRoundTrip_deposit_withdraw(uint amount) external virtual {
        // Deposit
        // vm.assume(amount < 1e9 && amount > 1e6);
        amount = bound(amount, 1e6, 1e12);

        startHoax(alice, alice);
        asset.approve(address(adapter), type(uint).max);
        uint initAliceBalance = asset.balanceOf(alice);
        uint initadapterBalance = asset.balanceOf(address(adapter));

        uint previewDeposit = adapter.previewDeposit(amount);
        uint deposit = adapter.deposit(amount, alice);

        assertApproxEqAbs(asset.balanceOf(alice), initAliceBalance - amount, tolerance, "improper amount decreased from alice's address");
        // assertEq(asset.balanceOf(address(adapter)), initadapterBalance + amount, "");
        assertGt(IERC20(gmdUSDC).balanceOf(address(adapter)), 0, "Adapter share balance shouldn't be zero");
        assertApproxEqAbs(adapter.balanceOf(alice), previewDeposit, tolerance, "Alice share value does not match quoted amount");
        assertApproxEqAbs(previewDeposit, deposit, tolerance ,"amount quoted to mint not matching actually minted amount");
        
        // Withdraw
        uint vaultPreBalance = IERC20(gmdUSDC).balanceOf(address(adapter));

        uint maxWithdraw = adapter.maxWithdraw(alice);

        uint previewWithdraw = adapter.previewWithdraw(maxWithdraw);

        uint shares_burnt = adapter.withdraw(maxWithdraw, alice, alice);

        assertApproxEqAbs(asset.balanceOf(alice), initAliceBalance, amount * 0.005e6 / 1e6, "alice balance not within reliable range at the end of test");
        assertApproxEqAbs(asset.balanceOf(address(adapter)), initadapterBalance, tolerance, "adapter balance is not same at end of test");
        assertApproxEqAbs(previewWithdraw, shares_burnt, tolerance, "shares burnt does not match quoted burn amount");
        assertLt(IERC20(gmdUSDC).balanceOf(address(adapter)), vaultPreBalance, "Adapter share balance did not decrease");
    }

    function testRoundTrip_mint_redeem(uint amount) external virtual {
        // Mint
        // vm.assume(amount < 1e9 && amount > 1e6);
        amount = bound(amount, 1e6, 1e12);

        startHoax(alice, alice);
        asset.approve(address(adapter), type(uint).max);
        uint initAliceBalance = asset.balanceOf(alice);
        uint initadapterBalance = asset.balanceOf(address(adapter));

        uint previewMint = adapter.previewMint(amount);
        uint mint = adapter.mint(amount, alice);

        assertEq(asset.balanceOf(alice), initAliceBalance - previewMint, "Alice's token balance not decreased by proper amount");
        assertGt(IERC20(gmdUSDC).balanceOf(address(adapter)), 0, "Adapter share balance shouldn't be zero");
        assertGt(adapter.balanceOf(alice), 0, "Alice Share value should not be zero");
        assertEq(previewMint, mint, "assets quoted to be transferred not matching actual amount");

        // Redeem
        uint previewRedeem = adapter.previewRedeem(amount);
        uint assets_converted = adapter.redeem(amount, alice, alice);

        assertApproxEqAbs(asset.balanceOf(alice), initAliceBalance, mint * 0.005e6 / 1e6, "alice balance not within reliable range at the end of test");
        assertApproxEqAbs(asset.balanceOf(address(adapter)), initadapterBalance, tolerance, "adapter balance is not same at end of test");

        assertGe(assets_converted, previewRedeem, "redeem NOT >= previewRedeem");
        assertApproxEqRel(previewRedeem, assets_converted, 0.001e18, "assets actually transferred to burn not same as quoted amount");
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