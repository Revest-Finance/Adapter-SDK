pragma solidity >= 0.8.0;
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "contracts/interfaces/IERC4626.sol";


abstract contract ExampleTests is Test {
    IERC4626 adapter;

    address vault;

    IERC20 asset;
    address angel = address(1);
    address alice = address(2);
    address bob = address(3);
    uint256 tolerance = 10;

    constructor(IERC4626 _adapter, uint256 _tolerance) {
        adapter = _adapter;
        tolerance = _tolerance;
        asset = IERC20(adapter.asset());
        // deal(address(asset), angel, 1e18);
        hoax(angel, angel);
        asset.approve(address(adapter), type(uint).max);
        
        deal(address(asset), alice, type(uint).max / 2);

        vm.label(vault, "vault");
        vm.label(address(adapter), "adapter");
        vm.label(address(asset), "asset");
        vm.label(alice, "alice");
        vm.label(angel, "angel");
        vm.label(bob, "bob");

    }

    function setUp() public {
         uint random = 1e18;
        startHoax(angel, angel);
        adapter.deposit(random, angel);
        // adapter.deposit(random / 2 * 1e18, angel);
        // adapter.deposit(random * 1e18, angel);
        vm.stopPrank();
    }

    // This is intended to be overridden
    function appreciateadapter(uint amount) public virtual {
        hoax(angel, angel);
        asset.transfer(address(adapter), amount);
    }

    //Verify previews = actual functions
    function testDeposit(uint256 amount) public virtual {
        vm.assume(amount < 1e52 && amount > 1e18);

        startHoax(alice, alice);
        asset.approve(address(adapter), amount);

        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        uint vaultBalance = asset.balanceOf(vault);

        uint preview = adapter.previewDeposit(amount);


        uint shares_minted = adapter.deposit(amount, alice);

        assertEq(asset.balanceOf(alice), aliceBalance - amount, "Alice Balance of Asset did not decrease by desired amount");
        assertGt(adapter.balanceOf(alice), 0, "Alice Balance should not be zero");

        assertEq(adapter.balanceOf(alice), shares_minted, "Alice's Share balance does not match shares minted");

        assertEq(asset.balanceOf(address(vault)), vaultBalance + amount, "Vault did not appreciate by amount deposited");
        assertEq(preview, shares_minted, "shares expected not matching shares minted to Alice");
    }

    function testMint(uint amount) public virtual {
        vm.assume(amount < 1e52 && amount > 1e18);

        startHoax(alice, alice);

        uint alicePreBal = adapter.balanceOf(alice);
        uint preview = adapter.previewMint(amount);

        asset.approve(address(adapter), preview);
        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        uint assets_used_to_mint = adapter.mint(amount, alice);

        assertEq(asset.balanceOf(alice), aliceBalance - preview);
        assertEq(asset.balanceOf(address(adapter)), adapterBalance + preview);
        assertEq(adapter.balanceOf(alice), alicePreBal + preview);
        assertEq(preview, assets_used_to_mint);
    }

    function testWithdraw(uint amount, uint withdrawAmount) public virtual {
        vm.assume(amount < 1e36 && amount > 1e18);
        vm.assume(withdrawAmount < amount && withdrawAmount >= 1e18);

        startHoax(alice, alice);

        asset.approve(address(adapter), amount);
        uint shares_received = adapter.deposit(amount, alice);

        uint aliceBalance = asset.balanceOf(alice);
        uint aliceAdapterBalance = adapter.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        uint preview = adapter.previewWithdraw(withdrawAmount);

        uint shares_burnt = adapter.withdraw(withdrawAmount, alice, alice);

        assertEq(asset.balanceOf(alice), aliceBalance + withdrawAmount);
        assertEq(adapter.balanceOf(alice), aliceAdapterBalance - preview);
        assertEq(asset.balanceOf(address(adapter)), adapterBalance - withdrawAmount);
        assertEq(preview, shares_burnt);
    }

    function testRedeem(uint amount, uint redeemAmount) public virtual {
        vm.assume(amount < 1e36 && amount > 0);
        vm.assume(redeemAmount <= amount && redeemAmount > 0);

        startHoax(alice, alice);

        asset.approve(address(adapter), amount);
        uint shares_received = adapter.mint(amount, alice);

        uint aliceBalance = asset.balanceOf(alice);
        uint adapterBalance = asset.balanceOf(address(adapter));
        uint preview = adapter.previewRedeem(redeemAmount);
        uint assets_withdrawn = adapter.redeem(redeemAmount, alice, alice);
        assertEq(asset.balanceOf(alice), aliceBalance + assets_withdrawn );
        assertEq(asset.balanceOf(address(adapter)), adapterBalance - redeemAmount);
        assertEq(preview, assets_withdrawn);
    }

    // Round trips
    function testRoundTrip_deposit_withdraw(uint amount) public virtual {
        // Deposit
        vm.assume(amount < 1e36 && amount > 0);

        startHoax(alice, alice);
        asset.approve(address(adapter), amount);
        uint initAliceBalance = asset.balanceOf(alice);
        uint initadapterBalance = asset.balanceOf(address(adapter));

        uint previewDeposit = adapter.previewDeposit(amount);
        uint deposit = adapter.deposit(amount, alice);

        assertEq(asset.balanceOf(alice), initAliceBalance - amount);
        assertEq(asset.balanceOf(address(adapter)), initadapterBalance + amount);
        assertEq(previewDeposit, deposit);
        
        // Withdraw
        uint previewWithdraw = adapter.previewWithdraw(amount);
        uint shares_burnt = adapter.withdraw(amount, alice, alice);

        assertApproxEqAbs(asset.balanceOf(alice), initAliceBalance, tolerance);
        assertApproxEqAbs(asset.balanceOf(address(adapter)), initadapterBalance, tolerance);
        assertEq(previewWithdraw, shares_burnt);
    }
    function testRoundTrip_mint_redeem(uint amount) public virtual {
        // Mint
        vm.assume(amount < 1e36 && amount > 0);

        startHoax(alice, alice);
        asset.approve(address(adapter), amount);
        uint initAliceBalance = asset.balanceOf(alice);
        uint initadapterBalance = asset.balanceOf(address(adapter));

        uint previewMint = adapter.previewMint(amount);
        uint mint = adapter.mint(amount, alice);

        assertEq(asset.balanceOf(alice), initAliceBalance - previewMint);
        assertEq(asset.balanceOf(address(adapter)), initadapterBalance + previewMint);
        assertEq(previewMint, mint);

        // Redeem
        uint previewRedeem = adapter.previewRedeem(amount);
        uint shares_converted = adapter.redeem(amount, alice, alice);

        assertApproxEqAbs(asset.balanceOf(alice), initAliceBalance, tolerance);
        assertApproxEqAbs(asset.balanceOf(address(adapter)), initadapterBalance, tolerance);
        assertApproxEqAbs(previewRedeem, shares_converted, tolerance);
    }

    function testWithdrawAllowance(uint amount) public virtual {
        vm.assume(amount < 1e36 && amount > 1e18);

        startHoax(alice, alice);
        asset.approve(address(adapter), type(uint).max);
        adapter.deposit(amount, alice);

        adapter.approve(bob, type(uint).max);

        assertGt(adapter.balanceOf(alice), 0, "Alice's deposit failed");

        uint preBalBob = asset.balanceOf(bob);
        vm.stopPrank();
        startHoax(bob, bob);

        // Withdraw
        uint previewWithdraw = adapter.previewWithdraw(amount);


        uint shares_burnt = adapter.withdraw(amount, bob, alice);

        assertEq(adapter.balanceOf(alice), 0, "alice should have no adapter shares after bob withdraws");
        assertGt(asset.balanceOf(bob), 0, "Bob asset balance should not be zero");
        assertGt(asset.balanceOf(bob), preBalBob, "Bob balance of asset did not appreciate by withdraw amount");
        assertEq(asset.balanceOf(bob), amount, "Bob's balance did not increase by expected amount");
    }

    function testFailWithdrawAllowance(uint amount) public virtual {
        vm.assume(amount < 1e36 && amount > 1e18);

        startHoax(alice, alice);
        asset.approve(address(adapter), type(uint).max);
        adapter.deposit(amount, alice);

        assertGt(adapter.balanceOf(alice), 0, "Alice's deposit failed");

        vm.stopPrank();
        startHoax(bob, bob);
        adapter.withdraw(amount, bob, alice);
    }

    function testMiscViewMethods(uint amount) public virtual {
        vm.assume(amount < 1e36 && amount > 1e18);

        startHoax(alice, alice);
        asset.approve(address(adapter), type(uint).max);
        adapter.deposit(amount, alice);

        adapter.maxDeposit(alice);
        adapter.maxRedeem(alice);
        adapter.maxMint(alice);
        adapter.maxWithdraw(alice);
    }
}