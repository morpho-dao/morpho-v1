const { expect } = require("chai");
const { utils, BigNumber } = require('ethers');
const cEthJson = require('../artifacts/contracts/interfaces/ICompound.sol/ICEth.json');


describe("CompoundModule Contract", () => {

  const WETH_ADDRESS = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B;
  const CETH_ADDRESS = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
  const DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  const CDAI_ADDRESS = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
  const COMPOUND_ORACLE_ADDRESS = 0x841616a5CBA946CF415Efe8a326A621A794D0f97;

  let cEthToken;
  let cDaiToken;
  let daiToken;
  let CompoundModule;
  let compoundModule;

  let owner;
  let lender;
  let borrower;
  let addrs;

  beforeEach(async () => {

    // CompoundModule
    CompoundModule = await ethers.getContractFactory("CompoundModule");
    [owner, lender, borrower, ...addrs] = await ethers.getSigners();
    compoundModule = await CompoundModule.deploy();
    await compoundModule.deployed();

    // CEth
    // CEth = await ethers.getContractFactory("ICEth");
    cEthToken = await new ethers.Contract(CETH_ADDRESS, cEthJson.abi, owner);
  });

  describe("Deployment", () => {
    it("Should deploy the contract", async () => {
      expect(await compoundModule.collateralFactor()).to.equal("750000000000000000");
      expect(await compoundModule.liquidationIncentive()).to.equal("8000");
      expect(await compoundModule.DENOMINATOR()).to.equal("10000");
    });
  });


  // UNITARY TESTS

  // lend

  describe("Lend function when there is no borrowers", () => {
    xit("Should have correct balances at the beginning", async () => {
      const ethAmount = utils.parseUnits("1");
      // expect(await lender.getBalance()).to.equal(ownerBalance);
      expect((await compoundModule.lendingBalanceOf(owner.getAddress())).onComp).to.equal(0);
      expect((await compoundModule.lendingBalanceOf(owner.getAddress())).onMorpho).to.equal(0);
    })

    xit("Should not work with amount 0", async () => {
      const ethAmount = utils.parseUnits("0");
      await expect(compoundModule.lend({ from: owner.getAddress(), value: ethAmount.toNumber() })).to.be.revertedWith("Amount cannot be 0");
    })

    it("Should have the right amount of cETH in onComp lending balance after", async () => {
      const ethAmount = utils.parseUnits("1");
      compoundModule.lend({ from: owner.getAddress(), value: ethAmount });
      expectedOnCompLendingBalance = await cEthToken.exchangeRateCurrent({ from: owner.getAddress() });
      console.log("exchange current rate :", expectedOnCompLendingBalance)
      expect(Number((await compoundModule.lendingBalanceOf(owner.getAddress())).onComp)).to.equal(expectedOnCompLendingBalance);
    })

    it("Should have the right amount of ETH in onMorpho lending balance after", async () => {
      const ethAmount = utils.parseUnits("1");
      compoundModule.lend({ from: owner.getAddress(), value: ethAmount });
      expectedOnMorphoLendingBalance = 0;
      expect((await compoundModule.lendingBalanceOf(owner.getAddress())).onMorpho).to.equal(expectedOnMorphoLendingBalance);
    })

    // it("Should should have the correct amount of ETH on Compound after", async () => {
    // })
  })

  // describe("Lend function when there is not enough borrowers", () => {
  // })

  // describe("Lend function when there is enough borrowers", () => {
  // })

  // describe("Lending / Borrowing", () => {
  //   it("Should lend 1 ETH", async () => {
  //     const ethAmount = utils.parseUnits("1");
  //     const lenderBalanceBefore = await lender.getBalance(lender.getAddress());
  //     const compoundModuleCEthBalanceBefore = await cEthToken.balanceOf(compoundModule.getAddress());
  //     expect(compoundModuleCEthBalanceBefore).to.equal(0);
  //     await compoundModule.lend({ from: lender, value: ethAmount });
  //     const lenderBalanceAfter = await lender.getBalance(lender.getAddress());
  //     expect(BigNumber.from(lenderBalanceAfter)).to.equal(BigNumber.from(lenderBalanceBefore).add(ethAmount));
  //   });
  // });
});