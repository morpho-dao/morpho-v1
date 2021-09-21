require('dotenv').config({ path: '../.env.local' });
const { expect } = require('chai');
const hre = require('hardhat');
const { ethers } = require('hardhat');
const { utils, BigNumber } = require('ethers');
const Decimal = require('decimal.js');

// Use mainnet ABIs
const daiAbi = require('./abis/Dai.json');
const usdcAbi = require('./abis/USDC.json');
const usdtAbi = require('./abis/USDT.json');
const uniAbi = require('./abis/UNI.json');
const CErc20ABI = require('./abis/CErc20.json');
const CEthABI = require('./abis/CEth.json');
const comptrollerABI = require('./abis/Comptroller.json');
const compoundOracleABI = require('./abis/UniswapAnchoredView.json');

describe('CompoundModule Contract', () => {
  const CETH_ADDRESS = '0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5';
  const CDAI_ADDRESS = '0x5d3a536e4d6dbd6114cc1ead35777bab948e3643';
  const CUSDC_ADDRESS = '0x39AA39c021dfbaE8faC545936693aC917d5E7563';
  const CUSDT_ADDRESS = '0xf650c3d88d12db855b8bf7d11be6c55a4e07dcc9';
  const CUNI_ADDRESS = '0x35a18000230da775cac24873d00ff85bccded550';
  const CMKR_ADDRESS = '0x95b4ef2869ebd94beb4eee400a99824bf5dc325b';
  const DAI_ADDRESS = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
  const USDC_ADDRESS = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';
  const USDT_ADDRESS = '0xdAC17F958D2ee523a2206206994597C13D831ec7';
  const UNI_ADDRESS = '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984';
  const PROXY_COMPTROLLER_ADDRESS = '0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B';

  const SCALE = BigNumber.from(10).pow(18);

  let cUsdcToken;
  let cDaiToken;
  let cUsdtToken;
  let cUniToken;
  let cMkrToken;
  let daiToken;
  let usdtToken;
  let uniToken;
  let CompoundModule;
  let compoundModule;

  let signers;
  let owner;
  let lender1;
  let lender2;
  let lender3;
  let borrower1;
  let borrower2;
  let borrower3;
  let liquidator;
  let addrs;
  let lenders;
  let borrowers;

  let underlyingThreshold;

  /* Utils functions */

  const underlyingToCToken = (underlyingAmount, exchangeRateCurrent) => {
    return underlyingAmount.mul(SCALE).div(exchangeRateCurrent);
  };

  const cTokenToUnderlying = (cTokenAmount, exchangeRateCurrent) => {
    return cTokenAmount.mul(exchangeRateCurrent).div(SCALE);
  };

  const underlyingToMUnit = (underlyingAmount, exchangeRateCurrent) => {
    return underlyingAmount.mul(SCALE).div(exchangeRateCurrent);
  };

  const mUnitToUnderlying = (mUnitAmount, exchangeRateCurrent) => {
    return mUnitAmount.mul(exchangeRateCurrent).div(SCALE);
  };

  const getCollateralRequired = (amount, collateralFactor, borrowedAssetPrice, collateralAssetPrice) => {
    return amount.mul(borrowedAssetPrice).div(collateralAssetPrice).mul(SCALE).div(collateralFactor);
  };

  const bigNumberMin = (a, b) => {
    if (a.lte(b)) return a;
    return b;
  };

  // To update exchangeRateCurrent
  // const doUpdate = await cDaiToken.exchangeRateCurrent();
  // await doUpdate.wait(1);
  // const erc = await cDaiToken.callStatic.exchangeRateStored();

  // Removes the last digits of a number: used to remove dust errors
  const removeDigitsBigNumber = (decimalsToRemove, number) => number.sub(number.mod(BigNumber.from(10).pow(decimalsToRemove))).div(BigNumber.from(10).pow(decimalsToRemove));
  const removeDigits = (decimalsToRemove, number) => (number - (number % 10 ** decimalsToRemove)) / 10 ** decimalsToRemove;

  const computeNewMorphoExchangeRate = (currentExchangeRate, BPY, currentBlockNumber, lastUpdateBlockNumber) => {
    // Use of decimal.js library for better accuracy
    const bpy = new Decimal(BPY.toString());
    const scale = new Decimal('1e18');
    const exponent = new Decimal(currentBlockNumber - lastUpdateBlockNumber);
    const val = bpy.div(scale).add(1);
    const multiplier = val.pow(exponent);
    const newExchangeRate = new Decimal(currentExchangeRate.toString()).mul(multiplier);
    return Decimal.round(newExchangeRate);
  };

  const computeNewBorrowIndex = (borrowRate, blockDelta, borrowIndex) => {
    return borrowRate.mul(blockDelta).mul(borrowIndex).div(SCALE).add(borrowIndex);
  };

  const to6Decimals = (value) => value.div(BigNumber.from(10).pow(12));

  beforeEach(async () => {
    // Users
    signers = await ethers.getSigners();
    [owner, lender1, lender2, lender3, borrower1, borrower2, borrower3, liquidator, ...addrs] = signers;
    lenders = [lender1, lender2, lender3];
    borrowers = [borrower1, borrower2, borrower3];

    // Deploy CompoundModule
    Morpho = await ethers.getContractFactory('Morpho');
    morpho = await Morpho.deploy(PROXY_COMPTROLLER_ADDRESS);
    await morpho.deployed();

    CompoundModule = await ethers.getContractFactory('CompoundModule');
    compoundModule = await CompoundModule.deploy(morpho.address, PROXY_COMPTROLLER_ADDRESS);
    await compoundModule.deployed();

    // Get contract dependencies
    cUsdcToken = await ethers.getContractAt(CErc20ABI, CUSDC_ADDRESS, owner);
    cDaiToken = await ethers.getContractAt(CErc20ABI, CDAI_ADDRESS, owner);
    cUsdtToken = await ethers.getContractAt(CErc20ABI, CUSDT_ADDRESS, owner);
    cUniToken = await ethers.getContractAt(CErc20ABI, CUNI_ADDRESS, owner);
    cMkrToken = await ethers.getContractAt(CErc20ABI, CMKR_ADDRESS, owner);
    usdtToken = await ethers.getContractAt(usdtAbi, USDT_ADDRESS, owner);
    comptroller = await ethers.getContractAt(comptrollerABI, PROXY_COMPTROLLER_ADDRESS, owner);
    compoundOracle = await ethers.getContractAt(compoundOracleABI, comptroller.oracle(), owner);

    const ethAmount = utils.parseUnits('100');

    // Mint some ERC20
    // Address of Join (has auth) https://changelog.makerdao.com/ -> releases -> contract addresses -> MCD_JOIN_DAI
    const daiMinter = '0x9759A6Ac90977b93B58547b4A71c78317f391A28';
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [daiMinter],
    });
    const daiSigner = await ethers.getSigner(daiMinter);
    daiToken = await ethers.getContractAt(daiAbi, DAI_ADDRESS, daiSigner);
    const daiAmount = utils.parseUnits('100000000');
    await hre.network.provider.send('hardhat_setBalance', [daiMinter, utils.hexValue(ethAmount)]);

    // Mint DAI to all lenders and borrowers
    await Promise.all(
      signers.map(async (signer) => {
        await daiToken.mint(signer.getAddress(), daiAmount, {
          from: daiMinter,
        });
      })
    );

    const usdcMinter = '0x5b6122c109b78c6755486966148c1d70a50a47d7';
    // const masterMinter = await usdcToken.masterMinter();
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [usdcMinter],
    });
    const usdcSigner = await ethers.getSigner(usdcMinter);
    usdcToken = await ethers.getContractAt(usdcAbi, USDC_ADDRESS, usdcSigner);
    const usdcAmount = BigNumber.from(10).pow(10); // 10 000 USDC
    await hre.network.provider.send('hardhat_setBalance', [usdcMinter, utils.hexValue(ethAmount)]);

    // Mint USDC
    await Promise.all(
      signers.map(async (signer) => {
        await usdcToken.mint(signer.getAddress(), usdcAmount, {
          from: usdcMinter,
        });
      })
    );

    const usdtWhale = '0x47ac0fb4f2d84898e4d9e7b4dab3c24507a6d503';
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [usdtWhale],
    });
    const usdtWhaleSigner = await ethers.getSigner(usdtWhale);
    usdcToken = await ethers.getContractAt(usdcAbi, USDC_ADDRESS, usdtWhaleSigner);
    const usdtAmount = BigNumber.from(10).pow(10); // 10 000 USDT
    await hre.network.provider.send('hardhat_setBalance', [usdtWhale, utils.hexValue(ethAmount)]);

    // Transfer USDT
    await Promise.all(
      signers.map(async (signer) => {
        await usdtToken.connect(usdtWhaleSigner).transfer(signer.getAddress(), usdtAmount);
      })
    );

    const uniMinter = '0x1a9c8182c09f50c8318d769245bea52c32be35bc';
    // const uni = '0x8546ecA807B4789b3734525456643fd8F239c795';
    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [uniMinter],
    });
    const uniSigner = await ethers.getSigner(uniMinter);
    uniToken = await ethers.getContractAt(uniAbi, UNI_ADDRESS, uniSigner);
    const uniAmount = utils.parseUnits('10000'); // 10 000 UNI
    await hre.network.provider.send('hardhat_setBalance', [uniMinter, utils.hexValue(ethAmount)]);

    // Transfer UNI
    await Promise.all(
      signers.map(async (signer) => {
        await uniToken.connect(uniSigner).transfer(signer.getAddress(), uniAmount);
      })
    );

    underlyingThreshold = BigNumber.from(1).pow(18);

    await morpho.connect(owner).setCompoundModule(compoundModule.address);
    await morpho.connect(owner).createMarkets([CDAI_ADDRESS, CUSDC_ADDRESS, CUSDT_ADDRESS, CUNI_ADDRESS]);
    await morpho.connect(owner).listMarket(CDAI_ADDRESS);
    await morpho.connect(owner).updateThreshold(CUSDC_ADDRESS, 0, BigNumber.from(1).pow(6));
    await morpho.connect(owner).listMarket(CUSDC_ADDRESS);
    await morpho.connect(owner).updateThreshold(CUSDT_ADDRESS, 0, BigNumber.from(1).pow(6));
    await morpho.connect(owner).listMarket(CUSDT_ADDRESS);
    await morpho.connect(owner).listMarket(CUNI_ADDRESS);
  });

  describe('Deployment', () => {
    it('Should deploy the contract with the right values', async () => {
      expect(await morpho.liquidationIncentive(CDAI_ADDRESS)).to.equal(utils.parseUnits('1.1'));

      // Calculate BPY
      const borrowRatePerBlock = await cDaiToken.borrowRatePerBlock();
      const supplyRatePerBlock = await cDaiToken.supplyRatePerBlock();
      const expectedBPY = borrowRatePerBlock.add(supplyRatePerBlock).div(2);
      expect(await morpho.BPY(CDAI_ADDRESS)).to.equal(expectedBPY);

      const result = await comptroller.markets(CDAI_ADDRESS);
      expect(await morpho.mUnitExchangeRate(CDAI_ADDRESS)).to.be.equal(utils.parseUnits('1'));
      expect(await morpho.closeFactor(CDAI_ADDRESS)).to.be.equal(utils.parseUnits('0.5'));
      expect(await morpho.collateralFactor(CDAI_ADDRESS)).to.be.equal(result.collateralFactorMantissa);

      // Thresholds
      underlyingThreshold = await morpho.thresholds(CDAI_ADDRESS, 0);
      expect(underlyingThreshold).to.be.equal(utils.parseUnits('1'));
      expect(await morpho.thresholds(CDAI_ADDRESS, 1)).to.be.equal(BigNumber.from(10).pow(7));
      expect(await morpho.thresholds(CDAI_ADDRESS, 2)).to.be.equal(utils.parseUnits('1'));
    });
  });

  describe('Governance functions', () => {
    it('Should revert when at least one of the markets in input is not a real market', async () => {
      expect(morpho.connect(owner).createMarkets([USDT_ADDRESS])).to.be.reverted;
      expect(morpho.connect(owner).createMarkets([CETH_ADDRESS, USDT_ADDRESS, CUNI_ADDRESS])).to.be.reverted;
      expect(morpho.connect(owner).createMarkets([CETH_ADDRESS, CUNI_ADDRESS])).not.be.reverted;
    });

    it('Only Owner should be able to create markets', async () => {
      expect(morpho.connect(lender1).createMarkets([CUNI_ADDRESS])).to.be.reverted;
      expect(morpho.connect(borrower1).createMarkets([CUNI_ADDRESS])).to.be.reverted;
      expect(morpho.connect(owner).createMarkets([CUNI_ADDRESS])).not.be.reverted;
    });

    it('Only Owner should be able to update thresholds', async () => {
      const newThreshold = utils.parseUnits('2');
      await morpho.connect(owner).updateThreshold(CUSDC_ADDRESS, 0, newThreshold);
      await morpho.connect(owner).updateThreshold(CUSDC_ADDRESS, 1, newThreshold);
      await morpho.connect(owner).updateThreshold(CUSDC_ADDRESS, 2, newThreshold);

      // Other accounts than Owner
      await expect(morpho.connect(lender1).updateThreshold(CUSDC_ADDRESS, 2, newThreshold)).to.be.reverted;
      await expect(morpho.connect(borrower1).updateThreshold(CUSDC_ADDRESS, 2, newThreshold)).to.be.reverted;
    });

    it('Only Owner should be allowed to list/unlisted a market', async () => {
      await morpho.connect(owner).createMarkets([CUNI_ADDRESS]);
      expect(morpho.connect(lender1).listMarket(CUNI_ADDRESS)).to.be.reverted;
      expect(morpho.connect(borrower1).listMarket(CUNI_ADDRESS)).to.be.reverted;
      expect(morpho.connect(lender1).unlistMarket(CUNI_ADDRESS)).to.be.reverted;
      expect(morpho.connect(borrower1).unlistMarket(CUNI_ADDRESS)).to.be.reverted;
      expect(morpho.connect(owner).listMarket(CUNI_ADDRESS)).not.to.be.reverted;
      expect(morpho.connect(owner).unlistMarket(CUNI_ADDRESS)).not.to.be.reverted;
    });

    it('Should create a market the with right values', async () => {
      const lendBPY = await cMkrToken.supplyRatePerBlock();
      const borrowBPY = await cMkrToken.borrowRatePerBlock();
      const { blockNumber } = await morpho.connect(owner).createMarkets([CMKR_ADDRESS]);
      expect(await morpho.isListed(CMKR_ADDRESS)).not.to.be.true;

      const BPY = lendBPY.add(borrowBPY).div(2);
      expect(await morpho.BPY(CMKR_ADDRESS)).to.equal(BPY);

      const { collateralFactorMantissa } = await comptroller.markets(CMKR_ADDRESS);
      expect(await morpho.collateralFactor(CMKR_ADDRESS)).to.equal(collateralFactorMantissa);

      expect(await morpho.closeFactor(CMKR_ADDRESS)).to.equal(utils.parseUnits('0.5'));
      expect(await morpho.mUnitExchangeRate(CMKR_ADDRESS)).to.equal(SCALE);
      expect(await morpho.liquidationIncentive(CMKR_ADDRESS)).to.equal(utils.parseUnits('1.1'));
      expect(await morpho.lastUpdateBlockNumber(CMKR_ADDRESS)).to.equal(blockNumber);
    });

    it('Only Owner should set the liquidation incentive of a market', async () => {
      const newLiquidationIncentive = utils.parseUnits('1.4');
      await morpho.connect(owner).setLiquidationIncentive(CDAI_ADDRESS, newLiquidationIncentive);
      expect(await morpho.liquidationIncentive(CDAI_ADDRESS)).to.equal(newLiquidationIncentive);
      expect(morpho.connect(lender1).setLiquidationIncentive(CDAI_ADDRESS, utils.parseUnits('1.1'))).to.be.reverted;
      expect(morpho.connect(borrower1).setLiquidationIncentive(CDAI_ADDRESS, utils.parseUnits('1.1'))).to.be.reverted;
    });

    it('Only Owner should set the close factor of a market', async () => {
      const newCloseFactor = utils.parseUnits('0.7');
      await morpho.connect(owner).setCloseFactor(CDAI_ADDRESS, newCloseFactor);
      expect(await morpho.closeFactor(CDAI_ADDRESS)).to.equal(newCloseFactor);
      expect(morpho.connect(lender1).setCloseFactor(CDAI_ADDRESS, utils.parseUnits('0.8'))).to.be.reverted;
      expect(morpho.connect(borrower1).setCloseFactor(CDAI_ADDRESS, utils.parseUnits('0.8'))).to.be.reverted;
    });
  });

  describe('Lenders on Compound (no borrowers)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho).to.equal(0);
    });

    it('Should revert when lending less than the required threshold', async () => {
      await expect(compoundModule.connect(lender1).deposit(CDAI_ADDRESS, underlyingThreshold.sub(1))).to.be.reverted;
    });

    it('Should have the correct balances after lending', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore = await daiToken.balanceOf(lender1.getAddress());
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
      await daiToken.connect(lender1).approve(compoundModule.address, amount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, amount);
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const exchangeRate = await cDaiToken.callStatic.exchangeRateCurrent();
      const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho).to.equal(0);
    });

    it('Should be able to redeem ERC20 right after lending up to max lending balance', async () => {
      const amount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(lender1.getAddress());
      await daiToken.connect(lender1).approve(compoundModule.address, amount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, amount);
      const daiBalanceAfter1 = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter1).to.equal(daiBalanceBefore1.sub(amount));

      const lendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const exchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const toWithdraw1 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate1);

      // TODO: improve this test to prevent attacks
      await expect(compoundModule.connect(lender1).redeem(toWithdraw1.add(utils.parseUnits('0.001')).toString())).to.be.reverted;

      // Update exchange rate
      await cDaiToken.connect(lender1).exchangeRateCurrent();
      const exchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const toWithdraw2 = cTokenToUnderlying(lendingBalanceOnComp, exchangeRate2);
      await compoundModule.connect(lender1).redeem(CDAI_ADDRESS, toWithdraw2);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());
      // Check ERC20 balance
      expect(daiBalanceAfter2).to.equal(daiBalanceBefore1.sub(amount).add(toWithdraw2));

      // Check cToken left are only dust in lending balance
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp).to.be.lt(1000);
      await expect(compoundModule.connect(lender1).redeem(CDAI_ADDRESS, utils.parseUnits('0.001'))).to.be.reverted;
    });

    it('Should be able to deposit more ERC20 after already having deposit ERC20', async () => {
      const amount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('10').mul(2);
      const daiBalanceBefore = await daiToken.balanceOf(lender1.getAddress());

      await daiToken.connect(lender1).approve(compoundModule.address, amountToApprove);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, amount);
      const exchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, amount);
      const exchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();

      // Check ERC20 balance
      const daiBalanceAfter = await daiToken.balanceOf(lender1.getAddress());
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.sub(amountToApprove));

      // Check lending balance
      const expectedLendingBalanceOnComp1 = underlyingToCToken(amount, exchangeRate1);
      const expectedLendingBalanceOnComp2 = underlyingToCToken(amount, exchangeRate2);
      const expectedLendingBalanceOnComp = expectedLendingBalanceOnComp1.add(expectedLendingBalanceOnComp2);
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp);
    });

    it('Several lenders should be able to deposit and have the correct balances', async () => {
      const amount = utils.parseUnits('10');
      let expectedCTokenBalance = BigNumber.from(0);

      for (const i in lenders) {
        const lender = lenders[i];
        const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(amount);
        await daiToken.connect(lender).approve(compoundModule.address, amount);
        await compoundModule.connect(lender).deposit(CDAI_ADDRESS, amount);
        const exchangeRate = await cDaiToken.callStatic.exchangeRateCurrent();
        const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const expectedLendingBalanceOnComp = underlyingToCToken(amount, exchangeRate);
        expectedCTokenBalance = expectedCTokenBalance.add(expectedLendingBalanceOnComp);
        expect(removeDigitsBigNumber(7, await cDaiToken.balanceOf(compoundModule.address))).to.equal(removeDigitsBigNumber(7, expectedCTokenBalance));
        expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender.getAddress())).onComp)).to.equal(removeDigitsBigNumber(4, expectedLendingBalanceOnComp));
        expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender.getAddress())).onMorpho).to.equal(0);
      }
    });
  });

  describe('Borrowers on Compound (no lenders)', () => {
    it('Should have correct balances at the beginning', async () => {
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.equal(0);
    });

    it('Should revert when providing 0 as collateral', async () => {
      await expect(compoundModule.connect(lender1).deposit(CDAI_ADDRESS, 0)).to.be.reverted;
    });

    it('Should revert when borrowing less than threshold', async () => {
      const amount = to6Decimals(utils.parseUnits('10'));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await expect(compoundModule.connect(lender1).borrow(CDAI_ADDRESS, amount)).to.be.reverted;
    });

    it('Should be able to borrow on Compound after providing collateral up to max', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, amount);
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInCToken = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp;
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(CUSDC_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());

      // Borrow
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, maxToBorrow);
      const borrowIndex = await cDaiToken.borrowIndex();
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());

      // Check borrower1 balances
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow));
      const borrowingBalanceOnCompInUnderlying = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp.mul(borrowIndex).div(SCALE);
      let diff;
      if (borrowingBalanceOnCompInUnderlying.gt(maxToBorrow)) diff = borrowingBalanceOnCompInUnderlying.sub(maxToBorrow);
      else diff = maxToBorrow.sub(borrowingBalanceOnCompInUnderlying);
      expect(removeDigitsBigNumber(1, diff)).to.equal(0);

      // Check Morpho balances
      expect(await daiToken.balanceOf(compoundModule.address)).to.equal(0);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address)).to.equal(maxToBorrow);
    });

    it('Should not be able to borrow more than max allowed given an amount of collateral', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, amount);
      const collateralBalanceInCToken = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp;
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(CUSDC_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      const moreThanMaxToBorrow = maxToBorrow.add(utils.parseUnits('0.0001'));

      // TODO: fix dust issue
      // This check does not pass when adding utils.parseUnits("0.00001") to maxToBorrow
      await expect(compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, moreThanMaxToBorrow)).to.be.reverted;
    });

    it('Several borrowers should be able to borrow and have the correct balances', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('10'));
      const borrowedAmount = utils.parseUnits('2');
      let expectedMorphoBorrowingBalance = BigNumber.from(0);
      let previousBorrowIndex = await cDaiToken.borrowIndex();

      for (const i in borrowers) {
        const borrower = borrowers[i];
        await usdcToken.connect(borrower).approve(compoundModule.address, collateralAmount);
        await compoundModule.connect(borrower).deposit(CUSDC_ADDRESS, collateralAmount);
        const daiBalanceBefore = await daiToken.balanceOf(borrower.getAddress());

        await compoundModule.connect(borrower).borrow(CDAI_ADDRESS, borrowedAmount);
        // We have one block delay from Compound
        const borrowIndex = await cDaiToken.borrowIndex();
        expectedMorphoBorrowingBalance = expectedMorphoBorrowingBalance.mul(borrowIndex).div(previousBorrowIndex).add(borrowedAmount);

        // All underlyings should have been sent to the borrower
        const daiBalanceAfter = await daiToken.balanceOf(borrower.getAddress());
        expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(borrowedAmount));
        const borrowingBalanceOnCompInUnderlying = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower.getAddress())).onComp.mul(borrowIndex).div(SCALE);
        let diff;
        if (borrowingBalanceOnCompInUnderlying.gt(borrowedAmount)) diff = borrowingBalanceOnCompInUnderlying.sub(borrowedAmount);
        else diff = borrowedAmount.sub(borrowingBalanceOnCompInUnderlying);
        expect(removeDigitsBigNumber(1, diff)).to.equal(0);
        // Update previous borrow index
        previousBorrowIndex = borrowIndex;
      }

      // Check Morpho balances
      expect(await daiToken.balanceOf(compoundModule.address)).to.equal(0);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address)).to.equal(expectedMorphoBorrowingBalance);
    });

    it('Borrower should be able to repay less than what is on Compound', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, amount);
      const collateralBalanceInCToken = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp;
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(CUSDC_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);

      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, maxToBorrow);
      const borrowingBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp;
      const borrowIndex1 = await cDaiToken.borrowIndex();
      const borrowingBalanceOnCompInUnderlying = borrowingBalanceOnComp.mul(borrowIndex1).div(SCALE);
      const toRepay = borrowingBalanceOnCompInUnderlying.div(2);
      await daiToken.connect(borrower1).approve(compoundModule.address, toRepay);
      const borrowIndex2 = await cDaiToken.borrowIndex();
      await compoundModule.connect(borrower1).repay(CDAI_ADDRESS, toRepay);
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());

      const expectedBalanceOnComp = borrowingBalanceOnComp.sub(borrowingBalanceOnCompInUnderlying.div(2).mul(SCALE).div(borrowIndex2));
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(expectedBalanceOnComp);
      expect(daiBalanceAfter).to.equal(daiBalanceBefore.add(maxToBorrow).sub(toRepay));
    });
  });

  describe('P2P interactions between lender and borrowers', () => {
    it('Lender should withdraw her liquidity while not enough cToken on Morpho contract', async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits('10');
      const daiBalanceBefore1 = await daiToken.balanceOf(lender1.getAddress());
      const expectedDaiBalanceAfter1 = daiBalanceBefore1.sub(lendingAmount);
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, lendingAmount);
      const daiBalanceAfter1 = await daiToken.balanceOf(lender1.getAddress());

      // Check ERC20 balance
      expect(daiBalanceAfter1).to.equal(expectedDaiBalanceAfter1);
      const cExchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const expectedLendingBalanceOnComp1 = underlyingToCToken(lendingAmount, cExchangeRate1);
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedLendingBalanceOnComp1);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp).to.equal(expectedLendingBalanceOnComp1);

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, collateralAmount);

      // Borrowers borrows lender1 amount
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, lendingAmount);

      // Check lender1 balances
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const mExchangeRate1 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const expectedLendingBalanceOnComp2 = expectedLendingBalanceOnComp1.sub(underlyingToCToken(lendingAmount, cExchangeRate2));
      const expectedLendingBalanceOnMorpho2 = underlyingToMUnit(lendingAmount, mExchangeRate1);
      const lendingBalanceOnComp2 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho2 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho;
      expect(lendingBalanceOnComp2).to.equal(expectedLendingBalanceOnComp2);
      expect(lendingBalanceOnMorpho2).to.equal(expectedLendingBalanceOnMorpho2);

      // Check borrower1 balances
      const expectedBorrowingBalanceOnMorpho1 = expectedLendingBalanceOnMorpho2;
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorpho1);

      // Compare remaining to withdraw and the cToken contract balance
      await morpho.connect(owner).updateMUnitExchangeRate(CDAI_ADDRESS);
      const mExchangeRate2 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await morpho.BPY(CDAI_ADDRESS), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(lender1.getAddress());
      const lendingBalanceOnComp3 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho3 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho;
      const cExchangeRate3 = await cDaiToken.callStatic.exchangeRateCurrent();
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = lendingBalanceOnCompInUnderlying.add(mUnitToUnderlying(lendingBalanceOnMorpho3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(lendingBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cDaiToken.balanceOf(compoundModule.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.gt(cTokenContractBalanceInUnderlying);

      // Expected borrowing balances
      const expectedMorphoBorrowingBalance = remainingToWithdraw.add(cTokenContractBalanceInUnderlying).sub(lendingBalanceOnCompInUnderlying);

      // Withdraw
      await compoundModule.connect(lender1).redeem(CDAI_ADDRESS, amountToWithdraw);
      const borrowIndex = await cDaiToken.borrowIndex();
      const expectedBorrowerBorrowingBalanceOnComp = expectedMorphoBorrowingBalance.mul(SCALE).div(borrowIndex);
      const borrowBalance = await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());

      // Check borrow balance of Morphof
      expect(removeDigitsBigNumber(6, borrowBalance)).to.equal(removeDigitsBigNumber(6, expectedMorphoBorrowingBalance));

      // Check lender1 underlying balance
      expect(removeDigitsBigNumber(1, daiBalanceAfter2)).to.equal(removeDigitsBigNumber(1, expectedDaiBalanceAfter2));

      // Check lending balances of lender1
      expect(removeDigitsBigNumber(1, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp)).to.equal(0);
      expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho)).to.equal(0);

      // Check borrowing balances of borrower1
      expect(removeDigitsBigNumber(6, (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp)).to.equal(
        removeDigitsBigNumber(6, expectedBorrowerBorrowingBalanceOnComp)
      );
      expect(removeDigitsBigNumber(4, (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho)).to.equal(0);
    });

    it('Lender should redeem her liquidity while enough cDaiToken on Morpho contract', async () => {
      const lendingAmount = utils.parseUnits('10');
      let lender;
      const expectedDaiBalance = await daiToken.balanceOf(lender1.getAddress());

      for (const i in lenders) {
        lender = lenders[i];
        const daiBalanceBefore = await daiToken.balanceOf(lender.getAddress());
        const expectedDaiBalanceAfter = daiBalanceBefore.sub(lendingAmount);
        await daiToken.connect(lender).approve(compoundModule.address, lendingAmount);
        await compoundModule.connect(lender).deposit(CDAI_ADDRESS, lendingAmount);
        const daiBalanceAfter = await daiToken.balanceOf(lender.getAddress());

        // Check ERC20 balance
        expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
        const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
        const expectedLendingBalanceOnComp = underlyingToCToken(lendingAmount, cExchangeRate);
        expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender.getAddress())).onComp)).to.equal(removeDigitsBigNumber(4, expectedLendingBalanceOnComp));
      }

      // Borrower provides collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, collateralAmount);

      const previousLender1LendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;

      // Borrowers borrows lender1 amount
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, lendingAmount);

      // Check lender1 balances
      const mExchangeRate1 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      // Expected balances of lender1
      const expectedLendingBalanceOnComp2 = previousLender1LendingBalanceOnComp.sub(underlyingToCToken(lendingAmount, cExchangeRate2));
      const expectedLendingBalanceOnMorpho2 = underlyingToMUnit(lendingAmount, mExchangeRate1);
      const lendingBalanceOnComp2 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho2 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho;
      expect(lendingBalanceOnComp2).to.equal(expectedLendingBalanceOnComp2);
      expect(lendingBalanceOnMorpho2).to.equal(expectedLendingBalanceOnMorpho2);

      // Check borrower1 balances
      const expectedBorrowingBalanceOnMorpho1 = expectedLendingBalanceOnMorpho2;
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorpho1);

      // Compare remaining to withdraw and the cToken contract balance
      await morpho.connect(owner).updateMUnitExchangeRate(CDAI_ADDRESS);
      const mExchangeRate2 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const mExchangeRate3 = computeNewMorphoExchangeRate(mExchangeRate2, await morpho.BPY(CDAI_ADDRESS), 1, 0).toString();
      const daiBalanceBefore2 = await daiToken.balanceOf(lender1.getAddress());
      const lendingBalanceOnComp3 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho3 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho;
      const cExchangeRate3 = await cDaiToken.callStatic.exchangeRateCurrent();
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp3, cExchangeRate3);
      const amountToWithdraw = lendingBalanceOnCompInUnderlying.add(mUnitToUnderlying(lendingBalanceOnMorpho3, mExchangeRate3));
      const expectedDaiBalanceAfter2 = daiBalanceBefore2.add(amountToWithdraw);
      const remainingToWithdraw = amountToWithdraw.sub(lendingBalanceOnCompInUnderlying);
      const cTokenContractBalanceInUnderlying = cTokenToUnderlying(await cDaiToken.balanceOf(compoundModule.address), cExchangeRate3);
      expect(remainingToWithdraw).to.be.lt(cTokenContractBalanceInUnderlying);

      // lender3 balances before the withdraw
      const lender3LendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender3.getAddress())).onComp;
      const lender3LendingBalanceOnMorpho = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender3.getAddress())).onMorpho;

      // lender2 balances before the withdraw
      const lender2LendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender2.getAddress())).onComp;
      const lender2LendingBalanceOnMorpho = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender2.getAddress())).onMorpho;

      // borrower1 balances before the withdraw
      const borrower1BorrowingBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp;
      const borrower1BorrowingBalanceOnMorpho = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho;

      // Withdraw
      await compoundModule.connect(lender1).redeem(CDAI_ADDRESS, amountToWithdraw);
      const cExchangeRate4 = await cDaiToken.callStatic.exchangeRateStored();
      const borrowBalance = await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address);
      const daiBalanceAfter2 = await daiToken.balanceOf(lender1.getAddress());

      const lender2LendingBalanceOnCompInUnderlying = cTokenToUnderlying(lender2LendingBalanceOnComp, cExchangeRate4);
      const amountToMove = bigNumberMin(lender2LendingBalanceOnCompInUnderlying, remainingToWithdraw);
      const mExchangeRate4 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const expectedLender2LendingBalanceOnComp = lender2LendingBalanceOnComp.sub(underlyingToCToken(amountToMove, cExchangeRate4));
      const expectedLender2LendingBalanceOnMorpho = lender2LendingBalanceOnMorpho.add(underlyingToMUnit(amountToMove, mExchangeRate4));

      // Check borrow balance of Morpho
      expect(borrowBalance).to.equal(0);

      // Check lender1 underlying balance
      expect(daiBalanceAfter2).to.equal(expectedDaiBalanceAfter2);

      // Check lending balances of lender1
      expect(removeDigitsBigNumber(1, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp)).to.equal(0);
      expect(removeDigitsBigNumber(4, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho)).to.equal(0);

      // Check lending balances of lender2: lender2 should have replaced lender1
      expect(removeDigitsBigNumber(1, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender2.getAddress())).onComp)).to.equal(removeDigitsBigNumber(1, expectedLender2LendingBalanceOnComp));
      expect(removeDigitsBigNumber(6, (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender2.getAddress())).onMorpho)).to.equal(
        removeDigitsBigNumber(6, expectedLender2LendingBalanceOnMorpho)
      );

      // Check lending balances of lender3: lender3 balances should not move
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender3.getAddress())).onComp).to.equal(lender3LendingBalanceOnComp);
      expect((await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender3.getAddress())).onMorpho).to.equal(lender3LendingBalanceOnMorpho);

      // Check borrowing balances of borrower1: borrower1 balances should not move (except interest earn meanwhile)
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(borrower1BorrowingBalanceOnComp);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.equal(borrower1BorrowingBalanceOnMorpho);
    });

    it('Borrower on Morpho only, should be able to repay all borrowing amount', async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits('10');
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, lendingAmount);

      // Borrower borrows half of the tokens
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = lendingAmount.div(2);

      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, collateralAmount);
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, toBorrow);

      const borrowerBalanceOnMorpho = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho;
      const BPY = await morpho.BPY(CDAI_ADDRESS);
      await morpho.updateMUnitExchangeRate(CDAI_ADDRESS);
      const mUnitExchangeRate = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      // WARNING: Should be one block but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(mUnitExchangeRate, BPY, 1, 0).toString();
      const toRepay = mUnitToUnderlying(borrowerBalanceOnMorpho, mExchangeRate);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await cDaiToken.balanceOf(compoundModule.address);

      // Repay
      await daiToken.connect(borrower1).approve(compoundModule.address, toRepay);
      await compoundModule.connect(borrower1).repay(CDAI_ADDRESS, toRepay);
      const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToCToken(toRepay, cExchangeRate));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      // TODO: implement interest for borrowers to complete this test as borrower's debt is not increasing here
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(0);
      // Commented here due to the pow function issue
      // expect(removeDigitsBigNumber(1, (await compoundModule.borrowingBalanceInOf(borrower1.getAddress())).onMorpho)).to.equal(0);

      // Check Morpho balances
      expect(await cDaiToken.balanceOf(compoundModule.address)).to.equal(expectedMorphoCTokenBalance);
      expect(await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address)).to.equal(0);
    });

    it('Borrower on Morpho and on Compound, should be able to repay all borrowing amount', async () => {
      // Lender deposits tokens
      const lendingAmount = utils.parseUnits('10');
      const amountToApprove = utils.parseUnits('100000000');
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, lendingAmount);

      // Borrower borrows two times the amount of tokens;
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, collateralAmount);
      const daiBalanceBefore = await daiToken.balanceOf(borrower1.getAddress());
      const toBorrow = lendingAmount.mul(2);
      const lendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, toBorrow);

      const cExchangeRate1 = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoBorrowingBalance1 = toBorrow.sub(cTokenToUnderlying(lendingBalanceOnComp, cExchangeRate1));
      const morphoBorrowingBalanceBefore1 = await cDaiToken.callStatic.borrowBalanceCurrent(compoundModule.address);
      expect(removeDigitsBigNumber(3, morphoBorrowingBalanceBefore1)).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowingBalance1));
      await daiToken.connect(borrower1).approve(compoundModule.address, amountToApprove);

      const borrowerBalanceOnMorpho = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho;
      const BPY = await morpho.BPY(CDAI_ADDRESS);
      const mUnitExchangeRate = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      // WARNING: Should be 2 blocks but the pow function used in contract is not accurate
      const mExchangeRate = computeNewMorphoExchangeRate(mUnitExchangeRate, BPY, 1, 0).toString();
      const borrowerBalanceOnMorphoInUnderlying = mUnitToUnderlying(borrowerBalanceOnMorpho, mExchangeRate);

      // Compute how much to repay
      const doUpdate = await cDaiToken.borrowBalanceCurrent(compoundModule.address);
      await doUpdate.wait(1);
      const morphoBorrowingBalanceBefore2 = await cDaiToken.borrowBalanceStored(compoundModule.address);
      const borrowIndex1 = await cDaiToken.borrowIndex();
      const borrowerBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp;
      const toRepay = borrowerBalanceOnComp.mul(borrowIndex1).div(SCALE).add(borrowerBalanceOnMorphoInUnderlying);
      const expectedDaiBalanceAfter = daiBalanceBefore.add(toBorrow).sub(toRepay);
      const previousMorphoCTokenBalance = await cDaiToken.balanceOf(compoundModule.address);

      // Repay
      await daiToken.connect(borrower1).approve(compoundModule.address, toRepay);
      const borrowIndex3 = await cDaiToken.callStatic.borrowIndex();
      await compoundModule.connect(borrower1).repay(CDAI_ADDRESS, toRepay);
      const cExchangeRate2 = await cDaiToken.callStatic.exchangeRateStored();
      const expectedMorphoCTokenBalance = previousMorphoCTokenBalance.add(underlyingToCToken(borrowerBalanceOnMorphoInUnderlying, cExchangeRate2));
      const expectedBalanceOnComp = borrowerBalanceOnComp.sub(borrowerBalanceOnComp.mul(borrowIndex1).div(borrowIndex3));

      // Check borrower1 balances
      const daiBalanceAfter = await daiToken.balanceOf(borrower1.getAddress());
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
      const borrower1BorrowingBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp;
      expect(removeDigitsBigNumber(2, borrower1BorrowingBalanceOnComp)).to.equal(removeDigitsBigNumber(2, expectedBalanceOnComp));
      // WARNING: Commented here due to the pow function issue
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.be.lt(1000000000000);

      // Check Morpho balances
      expect(removeDigitsBigNumber(5, await cDaiToken.balanceOf(compoundModule.address))).to.equal(removeDigitsBigNumber(5, expectedMorphoCTokenBalance));
      // Issue here: we cannot access the most updated borrowing balance as it's updated during the repayBorrow on Compound.
      // const expectedMorphoBorrowingBalance2 = morphoBorrowingBalanceBefore2.sub(borrowerBalanceOnComp.mul(borrowIndex2).div(SCALE));
      // expect(removeDigitsBigNumber(3, await cToken.callStatic.borrowBalanceStored(compoundModule.address))).to.equal(removeDigitsBigNumber(3, expectedMorphoBorrowingBalance2));
    });

    it('Should disconnect lender from Morpho when borrowing an asset that nobody has on morpho and the lending balance is partly used', async () => {
      // lender1 deposits DAI
      const lendingAmount = utils.parseUnits('100');
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, lendingAmount);

      // borrower1 deposits USDC as collateral
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, collateralAmount);

      // borrower1 borrows part of the lending amount of lender1
      const amountToBorrow = lendingAmount.div(2);
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, amountToBorrow);
      const borrowingBalanceOnMorpho = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho;

      // lender1 borrows USDT that nobody is lending on Morpho
      const cDaiExchangeRate1 = await cDaiToken.callStatic.exchangeRateCurrent();
      const mDaiExchangeRate1 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const lendingBalanceOnComp1 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const lendingBalanceOnMorpho1 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho;
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp1, cDaiExchangeRate1);
      const lendingBalanceMorphoInUnderlying = mUnitToUnderlying(lendingBalanceOnMorpho1, mDaiExchangeRate1);
      const lendingBalanceInUnderlying = lendingBalanceOnCompInUnderlying.add(lendingBalanceMorphoInUnderlying);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const usdtPriceMantissa = await compoundOracle.callStatic.getUnderlyingPrice(CUSDT_ADDRESS);
      const daiPriceMantissa = await compoundOracle.callStatic.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = lendingBalanceInUnderlying.mul(daiPriceMantissa).div(usdtPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      await compoundModule.connect(lender1).borrow(CUSDT_ADDRESS, maxToBorrow);

      // Check balances
      const lendingBalanceOnComp2 = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const borrowingBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp;
      const cDaiExchangeRate2 = await cDaiToken.callStatic.exchangeRateCurrent();
      const cDaiBorrowIndex = await cDaiToken.borrowIndex();
      const mDaiExchangeRate2 = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const expectedBorrowingBalanceOnComp = mUnitToUnderlying(borrowingBalanceOnMorpho, mDaiExchangeRate2).mul(SCALE).div(cDaiBorrowIndex);
      const usdtBorrowingBalance = (await compoundModule.borrowingBalanceInOf(CUSDT_ADDRESS, lender1.getAddress())).onComp;
      const cUsdtBorrowIndex = await cUsdtToken.borrowIndex();
      const usdtBorrowingBalanceInUnderlying = usdtBorrowingBalance.mul(cUsdtBorrowIndex).div(SCALE);
      expect(removeDigitsBigNumber(5, lendingBalanceOnComp2)).to.equal(removeDigitsBigNumber(5, underlyingToCToken(lendingBalanceInUnderlying, cDaiExchangeRate2)));
      expect(removeDigitsBigNumber(2, borrowingBalanceOnComp)).to.equal(removeDigitsBigNumber(2, expectedBorrowingBalanceOnComp));
      expect(removeDigitsBigNumber(1, usdtBorrowingBalanceInUnderlying)).to.equal(removeDigitsBigNumber(1, maxToBorrow));
    });

    it('Lender should be connected to borrowers already on Morpho when depositing', async () => {
      const collateralAmount = to6Decimals(utils.parseUnits('100'));
      const lendingAmount = utils.parseUnits('100');
      const borrowingAmount = utils.parseUnits('30');

      // borrower1 borrows
      await usdcToken.connect(borrower1).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, collateralAmount);
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, borrowingAmount);
      const borrower1BorrowingBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp;

      // borrower2 borrows
      await usdcToken.connect(borrower2).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower2).deposit(CUSDC_ADDRESS, collateralAmount);
      await compoundModule.connect(borrower2).borrow(CDAI_ADDRESS, borrowingAmount);
      const borrower2BorrowingBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower2.getAddress())).onComp;

      // borrower3 borrows
      await usdcToken.connect(borrower3).approve(compoundModule.address, collateralAmount);
      await compoundModule.connect(borrower3).deposit(CUSDC_ADDRESS, collateralAmount);
      await compoundModule.connect(borrower3).borrow(CDAI_ADDRESS, borrowingAmount);
      const borrower3BorrowingBalanceOnComp = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower3.getAddress())).onComp;

      // lender1 deposit
      await daiToken.connect(lender1).approve(compoundModule.address, lendingAmount);
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, lendingAmount);
      const cExchangeRate = await cDaiToken.callStatic.exchangeRateStored();
      const borrowIndex = await cDaiToken.borrowIndex();
      const mUnitExchangeRate = await morpho.mUnitExchangeRate(CDAI_ADDRESS);

      // Check balances
      const lendingBalanceOnMorpho = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onMorpho;
      const lendingBalanceOnComp = (await compoundModule.lendingBalanceInOf(CDAI_ADDRESS, lender1.getAddress())).onComp;
      const underlyingMatched = borrower1BorrowingBalanceOnComp.add(borrower2BorrowingBalanceOnComp).add(borrower3BorrowingBalanceOnComp).mul(borrowIndex).div(SCALE);
      expectedLendingBalanceOnMorpho = underlyingMatched.mul(SCALE).div(mUnitExchangeRate);
      expectedLendingBalanceOnComp = underlyingToCToken(lendingAmount.sub(underlyingMatched), cExchangeRate);
      expect(removeDigitsBigNumber(2, lendingBalanceOnMorpho)).to.equal(removeDigitsBigNumber(2, expectedLendingBalanceOnMorpho));
      expect(lendingBalanceOnComp).to.equal(expectedLendingBalanceOnComp);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.be.lte(1);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower2.getAddress())).onComp).to.be.lte(1);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower3.getAddress())).onComp).to.be.lte(1);
    });
  });

  describe('Test liquidation', () => {
    it('Borrower should be liquidated while lending (collateral) is only on Compound', async () => {
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, amount);
      const collateralBalanceInCToken = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp;
      const cExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const collateralBalanceInUnderlying = cTokenToUnderlying(collateralBalanceInCToken, cExchangeRate);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(CUSDC_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = collateralBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);

      // Borrow
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, maxToBorrow);
      const collateralBalanceBefore = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp;
      const borrowingBalanceBefore = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp;

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // Liquidate
      const toRepay = maxToBorrow.div(2);
      await daiToken.connect(liquidator).approve(compoundModule.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await compoundModule.connect(liquidator).liquidate(CDAI_ADDRESS, CUSDC_ADDRESS, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const borrowIndex = await cDaiToken.borrowIndex();
      const cUsdcExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const liquidationIncentive = await morpho.liquidationIncentive(CDAI_ADDRESS);
      const collateralAssetPrice = await compoundOracle.getUnderlyingPrice(CUSDC_ADDRESS);
      const borrowedAssetPrice = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const amountToSeize = toRepay.mul(borrowedAssetPrice).div(collateralAssetPrice).mul(liquidationIncentive).div(SCALE);
      const expectedCollateralBalanceAfter = collateralBalanceBefore.sub(underlyingToCToken(amountToSeize, cUsdcExchangeRate));
      const expectedBorrowingBalanceAfter = borrowingBalanceBefore.sub(toRepay.mul(SCALE).div(borrowIndex));
      const expectedUSDCBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check balances
      expect(removeDigitsBigNumber(6, (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp)).to.equal(removeDigitsBigNumber(6, expectedCollateralBalanceAfter));
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(expectedBorrowingBalanceAfter);
      expect(removeDigitsBigNumber(1, usdcBalanceAfter)).to.equal(removeDigitsBigNumber(1, expectedUSDCBalanceAfter));
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
    });

    it('Borrower should be liquidated while lending (collateral) is on Compound and on Morpho', async () => {
      await daiToken.connect(lender1).approve(compoundModule.address, utils.parseUnits('1000'));
      await compoundModule.connect(lender1).deposit(CDAI_ADDRESS, utils.parseUnits('1000'));

      // borrower1 deposits USDC as lending (collateral)
      const amount = to6Decimals(utils.parseUnits('100'));
      await usdcToken.connect(borrower1).approve(compoundModule.address, amount);
      await compoundModule.connect(borrower1).deposit(CUSDC_ADDRESS, amount);

      // borrower2 borrows part of lending of borrower1 -> borrower1 has lending on Morpho and on Compound
      const toBorrow = amount;
      await uniToken.connect(borrower2).approve(compoundModule.address, utils.parseUnits('200'));
      await compoundModule.connect(borrower2).deposit(CUNI_ADDRESS, utils.parseUnits('200'));
      await compoundModule.connect(borrower2).borrow(CUSDC_ADDRESS, toBorrow);

      // borrower1 borrows DAI
      const cUsdcExchangeRate1 = await cUsdcToken.callStatic.exchangeRateCurrent();
      const mUsdcExchangeRate1 = await morpho.mUnitExchangeRate(CUSDC_ADDRESS);
      const lendingBalanceOnComp1 = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp;
      const lendingBalanceOnMorpho1 = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onMorpho;
      const lendingBalanceOnCompInUnderlying = cTokenToUnderlying(lendingBalanceOnComp1, cUsdcExchangeRate1);
      const lendingBalanceMorphoInUnderlying = mUnitToUnderlying(lendingBalanceOnMorpho1, mUsdcExchangeRate1);
      const lendingBalanceInUnderlying = lendingBalanceOnCompInUnderlying.add(lendingBalanceMorphoInUnderlying);
      const { collateralFactorMantissa } = await comptroller.markets(CDAI_ADDRESS);
      const usdcPriceMantissa = await compoundOracle.getUnderlyingPrice(CUSDC_ADDRESS);
      const daiPriceMantissa = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const maxToBorrow = lendingBalanceInUnderlying.mul(usdcPriceMantissa).div(daiPriceMantissa).mul(collateralFactorMantissa).div(SCALE);
      await compoundModule.connect(borrower1).borrow(CDAI_ADDRESS, maxToBorrow);
      const collateralBalanceOnCompBefore = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp;
      const collateralBalanceOnMorphoBefore = (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onMorpho;
      const borrowingBalanceOnMorphoBefore = (await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho;

      // Mine block
      await hre.network.provider.send('evm_mine', []);

      // liquidator liquidates borrower1's position
      const closeFactor = await comptroller.closeFactorMantissa();
      const toRepay = maxToBorrow.mul(closeFactor).div(SCALE);
      await daiToken.connect(liquidator).approve(compoundModule.address, toRepay);
      const usdcBalanceBefore = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceBefore = await daiToken.balanceOf(liquidator.getAddress());
      await compoundModule.connect(liquidator).liquidate(CDAI_ADDRESS, CUSDC_ADDRESS, borrower1.getAddress(), toRepay);
      const usdcBalanceAfter = await usdcToken.balanceOf(liquidator.getAddress());
      const daiBalanceAfter = await daiToken.balanceOf(liquidator.getAddress());

      // Liquidation parameters
      const mDaiExchangeRate = await morpho.mUnitExchangeRate(CDAI_ADDRESS);
      const cUsdcExchangeRate = await cUsdcToken.callStatic.exchangeRateCurrent();
      const liquidationIncentive = await morpho.liquidationIncentive(CDAI_ADDRESS);
      const collateralAssetPrice = await compoundOracle.getUnderlyingPrice(CUSDC_ADDRESS);
      const borrowedAssetPrice = await compoundOracle.getUnderlyingPrice(CDAI_ADDRESS);
      const amountToSeize = toRepay.mul(borrowedAssetPrice).div(collateralAssetPrice).mul(liquidationIncentive).div(SCALE);
      const expectedCollateralBalanceOnMorphoAfter = collateralBalanceOnMorphoBefore.sub(amountToSeize.sub(cTokenToUnderlying(collateralBalanceOnCompBefore, cUsdcExchangeRate)));
      const expectedBorrowingBalanceOnMorphoAfter = borrowingBalanceOnMorphoBefore.sub(toRepay.mul(SCALE).div(mDaiExchangeRate));
      const expectedUSDCBalanceAfter = usdcBalanceBefore.add(amountToSeize);
      const expectedDaiBalanceAfter = daiBalanceBefore.sub(toRepay);

      // Check liquidatee balances
      expect((await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onComp).to.equal(0);
      expect(removeDigitsBigNumber(2, (await compoundModule.lendingBalanceInOf(CUSDC_ADDRESS, borrower1.getAddress())).onMorpho)).to.equal(
        removeDigitsBigNumber(2, expectedCollateralBalanceOnMorphoAfter)
      );
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.borrowingBalanceInOf(CDAI_ADDRESS, borrower1.getAddress())).onMorpho).to.equal(expectedBorrowingBalanceOnMorphoAfter);

      // Check liquidator balances
      expect(removeDigitsBigNumber(1, usdcBalanceAfter)).to.equal(removeDigitsBigNumber(1, expectedUSDCBalanceAfter));
      expect(daiBalanceAfter).to.equal(expectedDaiBalanceAfter);
    });
  });

  xdescribe('Test attacks', () => {
    it('Should not be DDOS by a lender or a group of lenders', async () => {});

    it('Should not be DDOS by a borrower or a group of borrowers', async () => {});

    it('Should not be subject to flash loan attacks', async () => {});

    it('Should not be subjected to Oracle Manipulation attacks', async () => {});
  });
});
