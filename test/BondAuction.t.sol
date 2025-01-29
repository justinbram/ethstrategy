pragma solidity ^0.8.20;

import {DutchAuctionTest} from "./DutchAuction.t.sol";
import {BondAuction} from "../src/BondAuction.sol";
import {DutchAuction} from "../src/DutchAuction.sol";
import {console} from "forge-std/console.sol";

contract BondAuctionTest is DutchAuctionTest {
  function setUp() public override {
    super.setUp();
    dutchAuction = new BondAuction(
      address(ethStrategy),
      address(governor),
      address(usdcToken)
    );
    vm.startPrank(address(governor));
    ethStrategy.grantRoles(address(dutchAuction), ethStrategy.MINTER_ROLE());
    dutchAuction.grantRoles(admin1.addr, dutchAuction.ADMIN_ROLE());
    dutchAuction.grantRoles(admin2.addr, dutchAuction.ADMIN_ROLE());
    vm.stopPrank();
  }

  function test_constructor_success() public {
    dutchAuction = new BondAuction(
      address(ethStrategy),
      address(governor),
      address(usdcToken)
    );
    assertEq(dutchAuction.ethStrategy(), address(ethStrategy), "ethStrategy not assigned correctly");
    assertEq(dutchAuction.paymentToken(), address(usdcToken), "paymentToken not assigned correctly");
    assertEq(dutchAuction.owner(), address(governor), "governor not assigned correctly");
  }

  function test_fill_success_1() public override {
    uint128 amountIn = calculateAmountIn(defaultAmount, uint64(block.timestamp), defaultDuration, defaultStartPrice, defaultEndPrice, uint64(block.timestamp), dutchAuction.decimals());
    mintAndApprove(alice, amountIn, address(dutchAuction), address(usdcToken));
    super.test_fill_success_1();

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), amountIn, "usdcToken balance not assigned correctly");
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amountOut, defaultAmount, "amount not assigned correctly");
    assertEq(_amountIn, amountIn, "amount not assigned correctly");
    assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
  }

  function test_fill_success_2() public override {
    uint128 _amount = defaultAmount - 1;
    mintAndApprove(alice, _amount * defaultStartPrice / (10**ethStrategy.decimals()), address(dutchAuction), address(usdcToken));
    super.test_fill_success_2();
    uint128 amountIn = calculateAmountIn(_amount, uint64(block.timestamp), defaultDuration, defaultStartPrice, defaultEndPrice, uint64(block.timestamp), dutchAuction.decimals());
    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), amountIn, "usdcToken balance not assigned correctly");
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amountOut, _amount, "amount not assigned correctly");
    assertEq(amountIn, _amountIn, "price not assigned correctly");
    assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
  }

  function test_redeem_success() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(block.timestamp + defaultDuration + 1);
    vm.prank(alice);
    bondAuction.redeem();
    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), defaultAmount, "ethStrategy balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(governor)), defaultAmount * defaultStartPrice / (10**ethStrategy.decimals()), "usdcToken balance not assigned correctly");

    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, 0, "amount not assigned correctly");
    assertEq(price, 0, "price not assigned correctly");
    assertEq(startRedemption, 0, "startRedemption not assigned correctly");
  }

  function test_redeem_noBondToRedeem() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(block.timestamp + defaultDuration + 1);
    vm.expectRevert(BondAuction.NoBondToRedeem.selector);
    bondAuction.redeem();
  }

  function test_redeem_redemptionWindowNotStarted() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(block.timestamp + defaultDuration - 1);
    vm.prank(alice);
    vm.expectRevert(BondAuction.RedemptionWindowNotStarted.selector);
    bondAuction.redeem();
    uint128 amountIn = calculateAmountIn(defaultAmount, uint64(block.timestamp), defaultDuration, defaultStartPrice, defaultEndPrice, uint64(block.timestamp), dutchAuction.decimals());
    (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amountOut, defaultAmount, "amount not assigned correctly");
    assertEq(amountIn, _amountIn, "price not assigned correctly");
    assertEq(startRedemption, block.timestamp + 1, "startRedemption not assigned correctly");
  }

  function test_redeem_redemptionWindowPassed() public {
    uint256 startTime = block.timestamp;
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(startTime + defaultDuration + bondAuction.REDEMPTION_WINDOW() + 1);
    vm.prank(alice);
    vm.expectRevert(BondAuction.RedemptionWindowPassed.selector);
    bondAuction.redeem();
    uint128 amountIn = calculateAmountIn(defaultAmount, uint64(block.timestamp), defaultDuration, defaultStartPrice, defaultEndPrice, uint64(block.timestamp), dutchAuction.decimals());
    (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amountOut, defaultAmount, "amount not assigned correctly");
    assertEq(amountIn, _amountIn, "price not assigned correctly");
    assertEq(startRedemption, startTime + defaultDuration, "startRedemption not assigned correctly");
  }

  function test_withdraw_success() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(block.timestamp + defaultDuration + 1);
    vm.prank(alice);
    bondAuction.withdraw();
    assertEq(usdcToken.balanceOf(alice), defaultAmount * defaultStartPrice / (10**ethStrategy.decimals()), "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), 0, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), 0, "ethStrategy balance not assigned correctly");

    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, 0, "amount not assigned correctly");
    assertEq(price, 0, "price not assigned correctly");
    assertEq(startRedemption, 0, "startRedemption not assigned correctly");
  }

  function test_withdraw_noBondToWithdraw() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.warp(block.timestamp + defaultDuration + 1);
    vm.expectRevert(BondAuction.NoBondToWithdraw.selector);
    bondAuction.withdraw();
    uint128 amountIn = calculateAmountIn(defaultAmount, uint64(block.timestamp), defaultDuration, defaultStartPrice, defaultEndPrice, uint64(block.timestamp), dutchAuction.decimals());
    (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amountOut, defaultAmount, "amount not assigned correctly");
    assertEq(_amountIn, amountIn, "price not assigned correctly");
    assertEq(startRedemption, block.timestamp - 1, "startRedemption not assigned correctly");
  }

  function test_withdraw_redemptionWindowNotStarted() public {
    test_fill_success_1();
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    vm.expectRevert(BondAuction.RedemptionWindowNotStarted.selector);
    vm.prank(alice);
    bondAuction.withdraw();
    uint128 amountIn = calculateAmountIn(defaultAmount, uint64(block.timestamp), defaultDuration, defaultStartPrice, defaultEndPrice, uint64(block.timestamp), dutchAuction.decimals());
    (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amountOut, defaultAmount, "amount not assigned correctly");
    assertEq(amountIn, _amountIn, "price not assigned correctly");
    assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
  }

  function test_fill_unredeemedBond() public {
    uint64 expectedStartTime = uint64(block.timestamp);
    uint128 _amount = defaultAmount / 2;
    uint128 amountIn = calculateAmountIn(_amount, uint64(block.timestamp), defaultDuration, defaultStartPrice, defaultEndPrice, uint64(block.timestamp), dutchAuction.decimals());
    mintAndApprove(alice, amountIn, address(dutchAuction), address(usdcToken));
    
    test_startAuction_success_1();
    vm.prank(alice);
    vm.expectEmit();
    emit DutchAuction.AuctionFilled(alice, _amount, amountIn);
    dutchAuction.fill(_amount);

    {
      (uint64 startTime, uint64 duration, uint128 startPrice, uint128 endPrice, uint128 amount) = dutchAuction.auction();
      assertEq(startTime, expectedStartTime, "startTime not assigned correctly");
      assertEq(duration, defaultDuration, "duration not assigned correctly");
      assertEq(startPrice, defaultStartPrice, "startPrice not assigned correctly");
      assertEq(endPrice, defaultEndPrice, "endPrice not assigned correctly");
      assertEq(amount, defaultAmount - _amount, "amount not assigned correctly");
    }

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), _amount * defaultStartPrice / (10**ethStrategy.decimals()), "usdcToken balance not assigned correctly");
    BondAuction bondAuction = BondAuction(address(dutchAuction));

    {
      (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
      assertEq(amount, _amount, "amount not assigned correctly");
      assertEq(price, amountIn, "price not assigned correctly");
      assertEq(startRedemption, block.timestamp + defaultDuration, "startRedemption not assigned correctly");
    }

    mintAndApprove(alice, _amount * defaultStartPrice, address(dutchAuction), address(usdcToken));
    vm.prank(alice);
    vm.expectRevert(BondAuction.UnredeemedBond.selector);
    dutchAuction.fill(_amount);
  }

  function testFuzz_fill(uint128 _amount, uint64 _startTime, uint64 _duration, uint128 _startPrice, uint128 _endPrice, uint64 _elapsedTime, uint128 _totalAmount) public virtual override {
    uint256 currentTime = block.timestamp;
    vm.assume(_amount > 0);
    vm.assume(_amount < _totalAmount);

    vm.assume(_startTime > currentTime);
    vm.assume(_startTime < currentTime + _duration);

    vm.assume(_duration > 0);
    vm.assume(_duration < dutchAuction.MAX_DURATION());

    vm.assume(_startPrice > 0);
    vm.assume(_startPrice >= _endPrice);
    vm.assume(_startPrice <= (type(uint128).max / defaultAmount));

    vm.assume(_endPrice > 0);
    vm.assume(_endPrice <= _startPrice);

    vm.assume(_elapsedTime >= _startTime);
    vm.assume(_elapsedTime < _startTime + _duration);

    vm.assume(_totalAmount > 0);
    vm.assume(_totalAmount > _amount);
    vm.assume(_totalAmount <= type(uint128).max / defaultStartPrice);

    vm.assume(_startPrice < type(uint128).max / _totalAmount);

    uint128 amountIn = calculateAmountIn(_amount, _startTime, _duration, _startPrice, _endPrice, _elapsedTime, dutchAuction.decimals());
    mintAndApprove(alice, amountIn, address(dutchAuction), address(usdcToken));
    fill(_amount, _startTime, _duration, _startPrice, _endPrice, _elapsedTime, _totalAmount);

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), amountIn, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), 0, "ethStrategy balance not assigned correctly");
    
    BondAuction bondAuction = BondAuction(address(dutchAuction));
    if(amountIn != 0) {
      (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
      uint256 __amount = _amount; // stack cycling
      assertEq(amountOut, __amount, "amount not assigned correctly");
      assertEq(_amountIn, amountIn, "price not assigned correctly");
      uint64 __startTime = _startTime; // stack cycling
      uint64 __duration = _duration; // stack cycling
      assertEq(startRedemption, __startTime + __duration, "startRedemption not assigned correctly");
    }
    else {
      (uint256 amountOut, uint256 _amountIn, uint256 startRedemption) = bondAuction.bonds(alice);
      assertEq(amountOut, 0, "amount not assigned correctly");
      assertEq(_amountIn, 0, "price not assigned correctly");
      assertEq(startRedemption, 0, "startRedemption not assigned correctly");
    }
  }

  function testFuzz_amount(uint128 _amount) public virtual override {
    vm.assume(_amount > 0);
    vm.assume(_amount < defaultAmount);
    uint64 currentTime = uint64(block.timestamp);
    uint128 amountIn = calculateAmountIn(_amount, currentTime, defaultDuration, defaultStartPrice, defaultEndPrice, currentTime, dutchAuction.decimals());
    vm.assume(amountIn != 0);
    mintAndApprove(alice, amountIn, address(dutchAuction), address(usdcToken));
    fill(_amount, currentTime, defaultDuration, defaultStartPrice, defaultEndPrice, currentTime, defaultAmount);

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), amountIn, "usdcToken balance not assigned correctly");

    BondAuction bondAuction = BondAuction(address(dutchAuction));
    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, _amount, "amount not assigned correctly");
    assertEq(price, amountIn, "amountIn not assigned correctly");
    assertEq(startRedemption, currentTime + defaultDuration, "startRedemption not assigned correctly");

    vm.warp(startRedemption);
    vm.prank(alice);
    bondAuction.redeem();
    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(governor)), amountIn, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), _amount, "ethStrategy balance not assigned correctly");
  }

  function testFuzz_startTime(uint64 _startTime) public virtual override {
    uint128 _amount = defaultAmount - 1;
    uint64 currentTime = uint64(block.timestamp);
    vm.assume(_startTime > currentTime);
    vm.assume(_startTime < currentTime + defaultDuration);
    uint128 amountIn = calculateAmountIn(_amount, _startTime, defaultDuration, defaultStartPrice, defaultEndPrice, currentTime, dutchAuction.decimals());
    vm.assume(amountIn != 0);
    mintAndApprove(alice, amountIn, address(dutchAuction), address(usdcToken));
    fill(_amount, currentTime, defaultDuration, defaultStartPrice, defaultEndPrice, currentTime, defaultAmount);

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), amountIn, "usdcToken balance not assigned correctly");

    BondAuction bondAuction = BondAuction(address(dutchAuction));
    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, _amount, "amount not assigned correctly");
    assertEq(price, amountIn, "amountIn not assigned correctly");
    assertEq(startRedemption, _startTime + defaultDuration, "startRedemption not assigned correctly");

    vm.warp(startRedemption);
    vm.prank(alice);
    bondAuction.redeem();
    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(governor)), amountIn, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), _amount, "ethStrategy balance not assigned correctly");
  }

  function testFuzz_duration(uint64 _duration) public virtual override {
    uint128 _amount = defaultAmount - 1;
    uint64 currentTime = uint64(block.timestamp);
    vm.assume(_duration > 0);
    vm.assume(_duration < dutchAuction.MAX_DURATION());
    uint128 amountIn = calculateAmountIn(_amount, currentTime, defaultDuration, defaultStartPrice, defaultEndPrice, currentTime, dutchAuction.decimals());
    vm.assume(amountIn != 0);
    mintAndApprove(alice, amountIn, address(dutchAuction), address(usdcToken));
    fill(_amount, currentTime, defaultDuration, defaultStartPrice, defaultEndPrice, currentTime, defaultAmount);

    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), amountIn, "usdcToken balance not assigned correctly");

    BondAuction bondAuction = BondAuction(address(dutchAuction));
    (uint256 amount, uint256 price, uint256 startRedemption) = bondAuction.bonds(alice);
    assertEq(amount, _amount, "amount not assigned correctly");
    assertEq(price, amountIn, "amountIn not assigned correctly");
    assertEq(startRedemption, currentTime + defaultDuration, "startRedemption not assigned correctly");

    vm.warp(startRedemption);
    vm.prank(alice);
    bondAuction.redeem();
    assertEq(usdcToken.balanceOf(alice), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(dutchAuction)), 0, "usdcToken balance not assigned correctly");
    assertEq(usdcToken.balanceOf(address(governor)), amountIn, "usdcToken balance not assigned correctly");
    assertEq(ethStrategy.balanceOf(alice), _amount, "ethStrategy balance not assigned correctly");
  }

  function testFuzz_startPrice(uint128 _startPrice) public virtual override {
    vm.assume(_startPrice > 0);
    vm.assume(_startPrice >= defaultEndPrice);
    vm.assume(_startPrice <= (type(uint128).max / defaultAmount));
    uint64 currentTime = uint64(block.timestamp);
    fill(defaultAmount - 1, currentTime, defaultDuration, _startPrice, defaultEndPrice, currentTime, defaultAmount);
  }

  function testFuzz_endPrice(uint128 _endPrice) public virtual override   {
    vm.assume(_endPrice > 0);
    vm.assume(_endPrice <= defaultStartPrice);
    uint64 currentTime = uint64(block.timestamp);
    fill(defaultAmount - 1, currentTime, defaultDuration, defaultStartPrice, _endPrice, currentTime, defaultAmount);
  }

  function testFuzz_elapsedTime(uint64 _elapsedTime) public virtual override {
    uint64 currentTime = uint64(block.timestamp);
    vm.assume(_elapsedTime > currentTime);
    vm.assume(_elapsedTime < currentTime + defaultDuration);
    fill(defaultAmount - 1, currentTime, defaultDuration, defaultStartPrice, defaultEndPrice, _elapsedTime, defaultAmount);
  }

  function testFuzz_totalAmount(uint128 _totalAmount) public virtual override {
    vm.assume(_totalAmount > 0);
    vm.assume(_totalAmount > defaultAmount);
    vm.assume(_totalAmount <= type(uint128).max / defaultStartPrice);
    uint64 currentTime = uint64(block.timestamp);
    fill(defaultAmount, currentTime, defaultDuration, defaultStartPrice, defaultEndPrice, currentTime, _totalAmount);
  }
}

