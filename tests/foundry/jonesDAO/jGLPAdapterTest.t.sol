pragma solidity >= 0.8.0;

import "forge-std/Test.sol";
import "contracts/adapters/jonesDAO/jGLPAdapter.sol";
import "../GenericAdapter.t.sol";
import "contracts/lib/ERC4626.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "contracts/lib/SafeTransferLib.sol";
import "contracts/interfaces/adapters/jonesDAO/IJonesRouter.sol";

interface whitelistController {
    function addToWhitelistContracts(address _account) external;
    function addToRole(bytes32 role, address _account) external;
}

interface GMXRouter {
    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
    function glpManager() external returns (address);
}

contract jGLPAdapterTest is Test {
    using SafeTransferLib for ERC20;

    jGLPAdapter adapter;
    
    address GLP = 0x4277f8F2c384827B5273592FF7CeBd9f2C1ac258;
    address vault = 0x7241bC8035b65865156DDb5EdEf3eB32874a3AF6;
    address router = 0x2F43c6475f1ecBD051cE486A9f3Ccc4b03F3d713;
    address jonesadapter = 0x42EfE3E686808ccA051A49BCDE34C5CbA2EBEfc1;
    address feeHelper = 0xEE5828181aFD52655457C2793833EbD7ccFE86Ac;
    address whitelist = 0x2ACc798DA9487fdD7F4F653e04D8E8411cd73e88;
    address gvrt = 0x17fF154A329E37282eb9a76C3ae848FC277F24C7;
    address sGLP = 0x5402B5F40310bDED796c7D0F3FF6683f5C0cFfdf;
    address USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    
    address GMXrouter = 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;

    ERC20 asset = ERC20(sGLP);
    ERC20 JGLP = ERC20(vault);

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
        console.log("address of this test: ", address(this));
        adapter = new jGLPAdapter(ERC20(sGLP), jonesadapter, router, vault, feeHelper, whitelist, gvrt, dustWallet);

        adapter.grantRole(SMART_WALLET, alice);
        adapter.grantRole(SMART_WALLET, angel);

        deal(address(USDC), angel, type(uint).max / 2);

        startHoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);
        ERC20(sGLP).safeApprove(address(adapter), type(uint).max);

        vm.stopPrank();

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

        startHoax(angel, angel);
        address GMXVault = 0x489ee077994B6658eAfA855C308275EAd8097C4A;
        ERC20(USDC).approve(GMXRouter(GMXrouter).glpManager(), type(uint).max);
        GMXRouter(GMXrouter).mintAndStakeGlp(USDC, 1e12, 1, 1);
        // require(ERC20(sGLP).balanceOf(angel) > 0, "sGLP is zero");

        deal(USDC, angel, type(uint).max);
        ERC20(USDC).safeApprove(jonesadapter, type(uint).max);
        IJonesAdapter(jonesadapter).depositStable(1e13, true);

        vm.stopPrank();
       
    }

    function setUp() public {
        uint random = 1e18;
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
        vm.assume(amount < 1e22 && amount > 1e18);

        startHoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);

        uint angelBalance = asset.balanceOf(angel);

        uint preBalance = JGLP.balanceOf(address(this));

        uint preview = adapter.previewDeposit(amount);

        uint deposit = adapter.deposit(amount, angel);

        console.log("DEPOSIT SUCCESSFUL");

        assertEq(asset.balanceOf(angel), angelBalance - amount, "Alice's account did not decrease by correct amount");
        assertGt(adapter.balanceOf(angel), 0, "Alice's Shares should not be zero");
        assertEq(adapter.balanceOf(angel), preview, "Shares minted to alice does not match quote");

        assertGt(JGLP.balanceOf(address(adapter)), preBalance, "JGLP Balance did not increase");

        assertGe(deposit, preview, "Alice shares should be deposit >= previewDeposit");
    }

    //Test a deposit and withdraw some amount less than deposit
    function testWithdraw(uint amount, uint withdrawAmount) external virtual {
        amount = bound(amount, 1e18, 1e22);
        withdrawAmount = bound(withdrawAmount, 1e17, amount / 2);
        // vm.assume(withdrawAmount < amount && withdrawAmount >= 1e6);

        startHoax(angel, angel);

        asset.approve(address(adapter), amount);
        uint shares_received = adapter.deposit(amount, angel);

        // deal(GLP, vault, 1e18);

        uint angelBalance = asset.balanceOf(angel);
        uint adapterBalance = JGLP.balanceOf(address(adapter));

        uint preview = adapter.previewWithdraw(withdrawAmount);
        uint shares_burnt = adapter.withdraw(withdrawAmount, angel, angel);
        
        assertEq(asset.balanceOf(angel), angelBalance + withdrawAmount, "Tokens not returned to alice from withdrawal");
        assertLt(JGLP.balanceOf(address(adapter)), adapterBalance, "Adapter Balance did not decrease");
        assertLe(shares_burnt, preview, "Shares actually burned should be <= previewWithdraw");
    }


    //test the mint function - Just mint some amount of tokens
    function testMint(uint amount) external virtual {
        vm.assume(amount < 1e22 && amount > 1e18); //picks some amount of tokens

        startHoax(angel, angel);


        uint preview = adapter.previewDeposit(amount); //how many shares can you get for amount of tokens

        uint angelBalance = asset.balanceOf(angel);
        uint adapterBalance = JGLP.balanceOf(address(adapter));
        uint angelShareBalance = adapter.balanceOf(angel);

        uint previewMint = adapter.previewMint(amount);
        uint assetsUsedtoMint = adapter.mint(amount, angel); //returns number of assets used to mint preview-shares

        assertEq(asset.balanceOf(angel), angelBalance - assetsUsedtoMint, "Alice's Asset balance did not decrease correctly");
        assertGt(JGLP.balanceOf(address(adapter)), adapterBalance, "Adapter Share balance should have increased");
        assertEq(adapter.balanceOf(angel), angelShareBalance + amount);
        assertLe(assetsUsedtoMint, previewMint, "Amount quoted does not match amount minted");
    }

    function testRedeem(uint amount, uint redeemAmount) external virtual {
        amount = bound(amount, 1e18+1, 1e22);
        vm.assume(redeemAmount < amount && redeemAmount > 1e18);

        startHoax(angel, angel);

        asset.approve(address(adapter), type(uint).max);
        uint shares_received = adapter.mint(amount, angel);

        uint angelTokenBalance = asset.balanceOf(angel);
        uint angelAdapterBalance = adapter.balanceOf(angel);
        uint adapterBalance = JGLP.balanceOf(address(adapter));

        uint previewRedeem = adapter.previewRedeem(redeemAmount); //expected assets gotten from redemption
        require(previewRedeem > 0);
        
        uint redeem = adapter.redeem(redeemAmount, angel, angel); //assets used to redeem that many shares
        
        assertGe(redeem, previewRedeem, "Actual assets used in redeem should be >= than those in previewRedeem");
        assertGe(asset.balanceOf(angel), angelTokenBalance + previewRedeem, "Correct amount of tokens not returned to alice");

        assertLt(JGLP.balanceOf(address(adapter)), adapterBalance, "Adapter Balance did not decrease");
        assertLt(adapter.balanceOf(angel), angelAdapterBalance, "Alice's share balance did not decrease");
        
        assertApproxEqAbs(previewRedeem, redeem, tolerance, "Shares redeemed does not equal shares quotes to be redeemed");

    }

    // Round trips
    function testRoundTrip_deposit_withdraw(uint amount) external virtual {
        vm.assume(amount < 1e22 && amount >= 1e18);

        startHoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);

        uint initAngelBalance = asset.balanceOf(angel);
        uint initadapterBalance = asset.balanceOf(address(adapter));

        uint previewDeposit = adapter.previewDeposit(amount);
        uint deposit = adapter.deposit(amount, angel);

        vm.roll(block.number + 1);
        appreciatejGLPVault();

        console.log("deposit successful");

        assertEq(asset.balanceOf(angel), initAngelBalance - amount, "improper amount decreased from angel's address");
        assertGt(JGLP.balanceOf(address(adapter)), 0, "Adapter share balance shouldn't be zero");
        assertEq(adapter.balanceOf(angel), previewDeposit, "angel share value does not match quoted amount");
        assertEq(previewDeposit, deposit, "amount quoted to mint not matching actually minted amount");
        
        console.log("passed first assertions");

        // Withdraw
        uint vaultPreBalance = JGLP.balanceOf(address(adapter));
        uint previewWithdraw = adapter.previewWithdraw(amount);

        console.log("amount to withdraw: ", amount);

        uint shares_burnt = adapter.withdraw(amount, angel, angel);

        console.log("withdraw successful");

        assertEq(asset.balanceOf(angel), initAngelBalance, "angel balance of assets not the same at the end of test");
        assertEq(asset.balanceOf(address(adapter)), initadapterBalance, "adapter balance is not same at end of test");
        assertEq(previewWithdraw, shares_burnt, "shares burnt does not match quoted burn amount");
        assertLe(shares_burnt, previewWithdraw, "withdraw <= previewWithdraw rule violated");
        assertLt(JGLP.balanceOf(address(adapter)), vaultPreBalance, "Adapter share balance did not decrease");
    }
    
    function testRoundTrip_mint_redeem(uint amount) external virtual {
        // Mint
        vm.assume(amount < 1e22 && amount > 1e18);

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

        //appreciate vault GLP
        appreciatejGLPVault();

        assertEq(asset.balanceOf(angel), initAngelBalance - previewMint, "angel's token balance not decreased by proper amount");
        assertGt(JGLP.balanceOf(address(adapter)), 0, "Adapter share balance shouldn't be zero");
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

        assertGe(asset.balanceOf(address(adapter)), initadapterBalance, "adapter balance is not same at end of test");
        assertEq(previewRedeem, shares_converted, "assets actually transferred to burn not same as quoted amount");
        assertGe(shares_converted, previewRedeem, "redeem >= previewRedeem rule violated");
    }

    function testWithdrawAllowance(uint amount) public virtual {
        vm.assume(amount < 1e22 && amount > 1e18);
       
        startHoax(angel, angel);

        uint shares_minted = adapter.deposit(amount, angel);
        
        appreciatejGLPVault();

        uint preview = adapter.previewWithdraw(amount);
        uint angelAdapterBalance = adapter.balanceOf(angel);
        uint angelBalance = asset.balanceOf(angel);
        uint adapterBalance = JGLP.balanceOf(address(adapter));

        adapter.approve(alice, type(uint).max);
        vm.stopPrank();

        startHoax(alice, alice);
        //Alice can withdraw shares on behalf of Angel. Withdrawing back to Angel just simplifies the test writing
        uint shares_burnt = adapter.withdraw(amount, angel, angel);

        assertEq(asset.balanceOf(angel), angelBalance + amount, "Angel Balance did not increase by expected after withdraw");

        assertEq(adapter.balanceOf(angel), angelAdapterBalance - preview, "Angel's adapter shares not decreasing by preview");
        assertLt(asset.balanceOf(address(adapter)), adapterBalance, "Adapter's JGLP-token Balance did not decrease");
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
        vm.assume(amount < 1e22 && amount > 1e18);

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

    function appreciatejGLPVault() internal {
        address holder = 0x15df56a82c194FeFEC9337C37A41964B69b584d5;

        uint preBal = ERC4626(vault).totalAssets();
        vm.stopPrank();
        
        startHoax(alice, alice);
        deal(USDC, alice, type(uint).max);
        ERC20(USDC).approve(GMXRouter(GMXrouter).glpManager(), type(uint).max);
        GMXRouter(GMXrouter).mintAndStakeGlp(USDC, 1e13, 1, 1);

        assertGt(ERC20(sGLP).balanceOf(alice), 0);
        ERC20(sGLP).transfer(holder, ERC20(sGLP).balanceOf(alice));

        uint afterBal = ERC4626(vault).totalAssets();

        // assertGt(afterBal, preBal, "total assets did not increase");

        vm.stopPrank();

        startHoax(angel);
    }

}