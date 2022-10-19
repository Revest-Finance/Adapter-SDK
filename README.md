# Adapter-SDK

In order to provide as many 4626-compliant adapters as possible for our customers, we have standardized our testing and development procedures to conform to a set of defined tests and standards. We have provided this list of requirements so that anyone can build and submit an adapter to to the Resonate Protocol. 

Anyone wishing to create a 4626-compliant vault adapter can build it and submit it for approval to Resonate provided it meets the required standards and passes the approved tests, defined below.

1. The Adapter must comply completely with the 4626-Vault-Standard
2. The adapter must expose the 4626-interface to the end-user, while providing the same functionality as an underlying defi-protocol.
  Example: ABC Protocol Vault allows you to deposit tokens using the depositTokens(uint) function, and withdraw using the withdrawTokens(uint) function. The adapter should accept tokens through its mint and deposit functions, and then pass them to the underlying vault's deposit functionality
The adapter should hold all of the shares given out by the underlying vault, instead issuing its own shares to those who deposit. If the vault is yUSDC, the adapter should hold all the yUSDC, giving its ownyaUSDC to the user.

3. The adapter should be permissionless, allowing anyone to interact outside of Resonate.
Our goal is to provide not only increased functionality for Resonate pools, but to further push for the adoption of 4626 by releasing these adapters as public-goods.

4. The adapter should not take any fees, but should be aware of any fees taken by the underlying yield-bearing-vault.

5. All adapters will be open-sourced.

## Required Tests

To be included in Resonate, your adapter must pass our defined testing standards. We have provided a skeleton, but as every adapter functions differently, you will need to write them yourselves. We recommend foundry. Your testing files must implement the `GenericAdapterTest` Interface provided below.

```
interface GenericAdapterTest {

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
```
