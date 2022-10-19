pragma solidity >= 0.8.0;

interface GenericAdapterTest {

    //Verify previews = actual functions
    function testDeposit(uint256 amount) external;

    function testMint(uint amount) external;

    function testWithdraw(uint amount, uint withdrawAmount) external;

    function testRedeem(uint amount, uint redeemAmount) external;

    function testRoundTrip_deposit_withdraw(uint amount) external;
    
    function testRoundTrip_mint_redeem(uint amount) external;

    function testWithdrawAllowance(uint amount) external;

    function testFailWithdrawAllowance(uint amount) external;

    function testMiscViewMethods(uint amount) external;
}