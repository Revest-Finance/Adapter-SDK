pragma solidity >= 0.8.0;

import "forge-std/Test.sol";
import "contracts/adapters/jonesDAO/jusdcAdapter.sol";
import "../GenericAdapter.t.sol";
import "contracts/lib/ERC4626.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface whitelistController {
    function addToWhitelistContracts(address _account) external;
    function addToRole(bytes32 role, address _account) external;
}

contract jusdcAdapterTest is Test {

    jusdcAdapter adapter;
    
    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address vault = 0xe66998533a1992ecE9eA99cDf47686F4fc8458E0;
    address router = 0x2F43c6475f1ecBD051cE486A9f3Ccc4b03F3d713;
    address jonesadapter = 0x42EfE3E686808ccA051A49BCDE34C5CbA2EBEfc1;
    address feeHelper = 0x86dd545514776245CC5d8243579e24ecd645895e;
    address whitelist = 0x2ACc798DA9487fdD7F4F653e04D8E8411cd73e88;
    address uvrt = 0xa485a0bc44988B95245D5F20497CCaFF58a73E99;

    ERC20 asset = ERC20(USDC);
    ERC20 JUSDC = ERC20(vault);

    address angel = address(1);
    address alice = address(2);
    address bob = address(3);
    address dustWallet = address(4);
    uint256 tolerance = 10;

    bytes32 private constant WHITELISTED_CONTRACTS = bytes32("WHITELISTED_CONTRACTS");
    bytes32 private constant RESONATE = "RESONATE"; //fees and whitelisted
    bytes32 public constant SMART_WALLET = 'SMART_WALLET'; //for the permissioned adapter

    address gov = 0xc8ce0aC725f914dBf1D743D51B6e222b79F479f1;

    constructor()  {

        adapter = new jusdcAdapter(asset, jonesadapter, router, vault, feeHelper, whitelist, uvrt, dustWallet);

        adapter.grantRole(SMART_WALLET, alice);
        adapter.grantRole(SMART_WALLET, angel);

        deal(address(asset), angel, type(uint).max / 2);
        hoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);
        deal(address(asset), alice, type(uint).max / 2);

        vm.label(vault, "vault");
        vm.label(address(adapter), "adapter");
        vm.label(address(asset), "asset");
        vm.label(address(router), "router");
        vm.label(address(whitelist), "whitelist");

        vm.label(alice, "alice");
        vm.label(angel, "angel");
        vm.label(bob, "bob");

        address owner = Ownable(whitelist).owner();
        hoax(owner, owner);
        whitelistController(whitelist).addToWhitelistContracts(address(adapter));

        hoax(gov, gov);
        whitelistController(whitelist).addToRole(bytes32("RESONATE"), address(adapter));
       
    }

    function setUp() public {
        uint random = 10e6;
        startHoax(angel, angel);
        adapter.deposit(random, address(0)); //Burn the shares
        // adapter.deposit(random / 2 * 1e18, angel);
        // adapter.deposit(random * 1e18, angel);
        vm.stopPrank();
    }

    function testSetup() public  {
       
    }

    // Test the deposit functionality
    function testDeposit(uint amount) external virtual {
        vm.assume(amount < 1e10 && amount > 1e6);

        startHoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);

        uint angelBalance = asset.balanceOf(angel);

        uint preBalance = JUSDC.balanceOf(address(this));

        uint preview = adapter.previewDeposit(amount);

        uint deposit = adapter.deposit(amount, angel);

        assertEq(asset.balanceOf(angel), angelBalance - amount, "Alice's account did not decrease by correct amount");
        assertGt(adapter.balanceOf(angel), 0, "Alice's Shares should not be zero");
        assertEq(adapter.balanceOf(angel), preview, "Shares minted to alice does not match quote");

        assertGt(JUSDC.balanceOf(address(adapter)), preBalance, "JUSDC Balance did not increase");

        assertGe(deposit, preview, "Alice shares should be deposit >= previewDeposit");
    }

    //Test a deposit and withdraw some amount less than deposit
    function testWithdraw(uint amount, uint withdrawAmount) external virtual {
        vm.assume(amount > 1e6 && amount < 1e12);
        vm.assume(withdrawAmount < amount / 2 && withdrawAmount >= 1e3);

        startHoax(angel, angel);

        asset.approve(address(adapter), amount);
        uint shares_received = adapter.deposit(amount, angel);

        // deal(USDC, vault, 1e18);

        uint angelBalance = asset.balanceOf(angel);
        uint adapterBalance = JUSDC.balanceOf(address(adapter));

        uint preview = adapter.previewWithdraw(withdrawAmount);
        uint shares_burnt = adapter.withdraw(withdrawAmount, angel, angel);
        
        assertEq(asset.balanceOf(angel), angelBalance + withdrawAmount, "Tokens not returned to alice from withdrawal");
        assertLt(JUSDC.balanceOf(address(adapter)), adapterBalance, "Adapter Balance did not decrease");
        assertLe(shares_burnt, preview, "Shares actually burned should be <= previewWithdraw");
    }


    //test the mint function - Just mint some amount of tokens
    function testMint(uint amount) external virtual {
        vm.assume(amount < 1e11 && amount > 1e6); //picks some amount of tokens

        startHoax(angel, angel);


        uint preview = adapter.previewDeposit(amount); //how many shares can you get for amount of tokens

        uint angelBalance = asset.balanceOf(angel);
        uint adapterBalance = JUSDC.balanceOf(address(adapter));
        uint angelShareBalance = adapter.balanceOf(angel);

        uint previewMint = adapter.previewMint(amount);
        uint assetsUsedtoMint = adapter.mint(amount, angel); //returns number of assets used to mint preview-shares

        assertEq(asset.balanceOf(angel), angelBalance - assetsUsedtoMint, "Alice's Asset balance did not decrease correctly");
        assertGt(JUSDC.balanceOf(address(adapter)), adapterBalance, "Adapter Share balance should have increased");
        assertEq(adapter.balanceOf(angel), angelShareBalance + amount);
        assertLe(assetsUsedtoMint, previewMint, "Amount quoted does not match amount minted");
    }

    function testRedeem(uint amount, uint redeemAmount) external virtual {
        amount = bound(amount, 1e6+1, 1e12);
        vm.assume(redeemAmount < amount && redeemAmount > 1e6);

        startHoax(angel, angel);

        asset.approve(address(adapter), type(uint).max);
        uint shares_received = adapter.mint(amount, angel);

        uint angelTokenBalance = asset.balanceOf(angel);
        uint angelAdapterBalance = adapter.balanceOf(angel);
        uint adapterBalance = JUSDC.balanceOf(address(adapter));

        uint previewRedeem = adapter.previewRedeem(redeemAmount); //expected assets gotten from redemption
        require(previewRedeem > 0);
        
        uint redeem = adapter.redeem(redeemAmount, angel, angel); //assets used to redeem that many shares
        
        assertGe(redeem, previewRedeem, "Actual assets used in redeem should be >= than those in previewRedeem");
        assertGe(asset.balanceOf(angel), angelTokenBalance + previewRedeem, "Correct amount of tokens not returned to alice");

        assertLt(JUSDC.balanceOf(address(adapter)), adapterBalance, "Adapter Balance did not decrease");
        assertLt(adapter.balanceOf(angel), angelAdapterBalance, "Alice's share balance did not decrease");
        
        assertEq(previewRedeem, redeem, "Shares redeemed does not equal shares quotes to be redeemed");

    }

    // Round trips
    function testRoundTrip_deposit_withdraw(uint amount) external virtual {
        vm.assume(amount < 1e12 && amount >= 1e6);

        startHoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);

        uint initAngelBalance = asset.balanceOf(angel);
        uint initadapterBalance = asset.balanceOf(address(adapter));

        uint previewDeposit = adapter.previewDeposit(amount);
        uint deposit = adapter.deposit(amount, angel);

        vm.roll(block.number + 1);
        deal(USDC, uvrt, asset.balanceOf(uvrt) + 1e13);

        console.log("deposit successful");

        assertEq(asset.balanceOf(angel), initAngelBalance - amount, "improper amount decreased from angel's address");
        assertGt(JUSDC.balanceOf(address(adapter)), 0, "Adapter share balance shouldn't be zero");
        assertEq(adapter.balanceOf(angel), previewDeposit, "angel share value does not match quoted amount");
        assertEq(previewDeposit, deposit, "amount quoted to mint not matching actually minted amount");
        
        console.log("passed first assertions");

        // Withdraw
        uint vaultPreBalance = JUSDC.balanceOf(address(adapter));
        uint previewWithdraw = adapter.previewWithdraw(amount);

        console.log("amount to withdraw: ", amount);

        uint shares_burnt = adapter.withdraw(amount, angel, angel);

        console.log("withdraw successful");

        assertEq(asset.balanceOf(angel), initAngelBalance, "angel balance of assets not the same at the end of test");
        assertEq(asset.balanceOf(address(adapter)), initadapterBalance, "adapter balance is not same at end of test");
        assertEq(previewWithdraw, shares_burnt, "shares burnt does not match quoted burn amount");
        assertLe(shares_burnt, previewWithdraw, "withdraw <= previewWithdraw rule violated");
        assertLt(JUSDC.balanceOf(address(adapter)), vaultPreBalance, "Adapter share balance did not decrease");
    }
    
    function testRoundTrip_mint_redeem(uint amount) external virtual {
        // Mint
        vm.assume(amount < 1e12 && amount > 1e6);

        startHoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);
        uint initAngelBalance = asset.balanceOf(angel);
        uint initadapterBalance = asset.balanceOf(address(adapter));

        uint preAssets = adapter.totalAssets();
        console.log("total supply before mint: ", adapter.totalSupply());
        console.log("total assets before mint: ", preAssets);

        uint previewMint = adapter.previewMint(amount);
        uint mint = adapter.mint(amount, angel);
        console.log("mint: ", mint);

        //appreciate vault USDC
        deal(USDC, uvrt, asset.balanceOf(uvrt) + 1e12);

        assertEq(asset.balanceOf(angel), initAngelBalance - previewMint, "angel's token balance not decreased by proper amount");
        assertGt(JUSDC.balanceOf(address(adapter)), 0, "Adapter share balance shouldn't be zero");
        assertGt(adapter.balanceOf(angel), 0, "angel Share value should not be zero");
        assertEq(previewMint, mint, "assets quoted to be transferred not matching actual amount");
        
        //Can't be used since fees are taken
        // assertEq(adapter.totalAssets(), preAssets + mint, "adapter assets did not increase by expected amount");
        console.log("total assets: ", adapter.totalAssets());

        // Redeem
        uint previewRedeem = adapter.previewRedeem(amount);
        console.log("Preview Redeem: ", previewRedeem);
        uint shares_converted = adapter.redeem(amount, angel, angel);
        console.log("shares converted to assets: ", shares_converted);
        
        //We can't do a round-trip cause of withdrawal fees so i just appreciated it and checked that we got more back
        assertGe(asset.balanceOf(angel), initAngelBalance, "angel balance of assets not the same at the end of test");

        assertEq(asset.balanceOf(address(adapter)), initadapterBalance, "adapter balance is not same at end of test");
        assertEq(previewRedeem, shares_converted, "assets actually transferred to burn not same as quoted amount");
        assertGe(shares_converted, previewRedeem, "redeem >= previewRedeem rule violated");
    }

    function testWithdrawAllowance(uint amount) public virtual {
        vm.assume(amount < 1e11 && amount > 1e6);
       
        startHoax(angel, angel);

        uint shares_minted = adapter.deposit(amount, angel);

        deal(USDC, uvrt, asset.balanceOf(uvrt) + 1e12);


        uint preview = adapter.previewWithdraw(amount);
        uint angelAdapterBalance = adapter.balanceOf(angel);
        uint angelBalance = asset.balanceOf(angel);
        uint adapterBalance = JUSDC.balanceOf(address(adapter));

        adapter.approve(alice, type(uint).max);
        vm.stopPrank();

        startHoax(alice, alice);
        //Alice can withdraw shares on behalf of Angel. Withdrawing back to Angel just simplifies the test writing
        uint shares_burnt = adapter.withdraw(amount, angel, angel);

        assertEq(asset.balanceOf(angel), angelBalance + amount, "Angel Balance did not increase by expected after withdraw");

        assertEq(adapter.balanceOf(angel), angelAdapterBalance - preview, "Angel's adapter shares not decreasing by preview");
        assertLt(asset.balanceOf(address(adapter)), adapterBalance, "Adapter's JUSDC-token Balance did not decrease");
        assertLe(shares_burnt, preview, "Invariant violated!");
    }

    function testFailWithdrawAllowance(uint amount) public virtual {
        startHoax(angel, angel);

        asset.approve(address(adapter), amount);
        adapter.deposit(amount, angel);

        vm.stopPrank();

        startHoax(alice, alice);
        adapter.withdraw(amount, angel, angel);
    }

    function testMiscViewMethods(uint amount) external virtual {
        vm.assume(amount < 1e11 && amount > 1e6);

        startHoax(angel, angel);
        adapter.deposit(amount, angel);

        uint maxDeposit = adapter.maxDeposit(angel);
        uint maxRedeem = adapter.maxRedeem(angel);
        uint maxMint = adapter.maxMint(angel);
        uint maxWithdraw = adapter.maxWithdraw(angel);

        assertGt(maxDeposit, 0, "maxDeposit should not be zero");
        assertGt(maxRedeem, 0, "maxRedeem should not be zero");
        assertGt(maxMint, 0, "maxMint should not be zero");
        assertGt(maxWithdraw, 0, "maxWithdraw should not be zero");
    }

}