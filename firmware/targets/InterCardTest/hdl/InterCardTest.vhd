-------------------------------------------------------------------------------
-- File       : InterCardTest.vhd
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: TimeTool PCIe card with PGPv2b
-------------------------------------------------------------------------------
-- This file is part of 'axi-pcie-dev'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'axi-pcie-dev', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiPkg.all;
use surf.AxiStreamPkg.all;
use surf.SsiPkg.all;

library axi_pcie_core;
use axi_pcie_core.AxiPciePkg.all;

library timetool;
use timetool.AppPkg.all;

entity InterCardTest is
   generic (
      TPD_G          : time    := 1 ns;
      ROGUE_SIM_EN_G : boolean := false;
      PGP_TYPE_G     : boolean := false;  -- False: PGPv2b@3.125Gb/s, True: PGPv3@10.3125Gb/s
      BUILD_INFO_G   : BuildInfoType);
   port (
      --------------
      --  Core Ports
      --------------
      -- System Ports
      emcClk       : in  sl;
      userClkP     : in  sl;
      userClkN     : in  sl;
      -- QSFP[0] Ports
      qsfp0RstL    : out sl;
      qsfp0LpMode  : out sl;
      qsfp0ModSelL : out sl;
      qsfp0ModPrsL : in  sl;
      -- QSFP[1] Ports
      qsfp1RstL    : out sl;
      qsfp1LpMode  : out sl;
      qsfp1ModSelL : out sl;
      qsfp1ModPrsL : in  sl;
      -- Boot Memory Ports 
      flashCsL     : out sl;
      flashMosi    : out sl;
      flashMiso    : in  sl;
      flashHoldL   : out sl;
      flashWp      : out sl;
      -- PCIe Ports
      pciRstL      : in  sl;
      pciRefClkP   : in  sl;
      pciRefClkN   : in  sl;
      pciRxP       : in  slv(7 downto 0);
      pciRxN       : in  slv(7 downto 0);
      pciTxP       : out slv(7 downto 0);
      pciTxN       : out slv(7 downto 0));
end InterCardTest;

architecture top_level of InterCardTest is

   constant DMA_LANES_C : positive := 8;

   constant NUM_AXIL_MASTERS_C : positive := 3;

   constant AXIL_CONFIG_C : 
      AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, x"0080_0000", 23, 20);

   signal userClk156 : sl;

   signal axilClk          : sl;
   signal axilRst          : sl;
   signal axilReadMaster   : AxiLiteReadMasterType;
   signal axilReadSlave    : AxiLiteReadSlaveType;
   signal axilWriteMaster  : AxiLiteWriteMasterType;
   signal axilWriteSlave   : AxiLiteWriteSlaveType;
   signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0);

   signal dmaClk       : sl;
   signal dmaRst       : sl;
   signal dmaObMasters : AxiStreamMasterArray(DMA_LANES_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
   signal dmaObSlaves  : AxiStreamSlaveArray(DMA_LANES_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);
   signal dmaIbMasters : AxiStreamMasterArray(DMA_LANES_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
   signal dmaIbSlaves  : AxiStreamSlaveArray(DMA_LANES_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);

   signal pipIbMaster : AxiWriteMasterType;
   signal pipIbSlave  : AxiWriteSlaveType;
   signal pipObMaster : AxiWriteMasterType;
   signal pipObSlave  : AxiWriteSlaveType;

   signal usrReadMaster  : AxiReadMasterType;
   signal usrReadSlave   : AxiReadSlaveType;
   signal usrWriteMaster : AxiWriteMasterType;
   signal usrWriteSlave  : AxiWriteSlaveType;

   signal strObMasters : AxiStreamMasterArray(0 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
   signal strObSlaves  : AxiStreamSlaveArray(0 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);
   signal strIbMasters : AxiStreamMasterArray(0 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
   signal strIbSlaves  : AxiStreamSlaveArray(0 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);

begin

   --------------------------------------- 
   -- AXI-Lite and reference 25 MHz clocks
   --------------------------------------- 
   U_axilClk : entity surf.ClockManagerUltraScale
      generic map(
         TPD_G             => TPD_G,
         SIMULATION_G      => ROGUE_SIM_EN_G,
         TYPE_G            => "PLL",
         INPUT_BUFG_G      => true,
         FB_BUFG_G         => true,
         RST_IN_POLARITY_G => '1',
         NUM_CLOCKS_G      => 1,
         -- MMCM attributes
         CLKIN_PERIOD_G    => 6.4,      -- 156.25 MHz
         CLKFBOUT_MULT_G   => 8,        -- 1.25GHz = 8 x 156.25 MHz
         CLKOUT0_DIVIDE_G  => 8,        -- 156.25MHz = 1.25GHz/8
         CLKOUT1_DIVIDE_G  => 50)       -- 25MHz = 1.25GHz/50

      port map(
         -- Clock Input
         clkIn     => userClk156,
         rstIn     => dmaRst,
         -- Clock Outputs
         clkOut(0) => axilClk,
         -- Reset Outputs
         rstOut(0) => axilRst);

   ----------------------- 
   -- AXI-PCIE-CORE Module
   -----------------------          
   U_Core : entity axi_pcie_core.XilinxKcu1500Core
      generic map (
         TPD_G                => TPD_G,
         ROGUE_SIM_EN_G       => ROGUE_SIM_EN_G,
         ROGUE_SIM_CH_COUNT_G => 4,     -- 4 Virtual Channels per DMA lane
         BUILD_INFO_G         => BUILD_INFO_G,
         DMA_AXIS_CONFIG_G    => DMA_AXIS_CONFIG_C,
         DMA_SIZE_G           => DMA_LANES_C)
      port map (
         ------------------------      
         --  Top Level Interfaces
         ------------------------        
         userClk156     => userClk156,
         -- DMA Interfaces
         dmaClk         => dmaClk,
         dmaRst         => dmaRst,
         dmaObMasters   => dmaObMasters,
         dmaObSlaves    => dmaObSlaves,
         dmaIbMasters   => dmaIbMasters,
         dmaIbSlaves    => dmaIbSlaves,
         -- User General Purpose AXI4 Interfaces (dmaClk domain)
         usrReadMaster   => usrReadMaster,
         usrReadSlave    => usrReadSlave,
         usrWriteMaster  => usrWriteMaster,
         usrWriteSlave   => usrWriteSlave,
         -- AXI-Lite Interface
         appClk         => axilClk,
         appRst         => axilRst,
         appReadMaster  => axilReadMaster,
         appReadSlave   => axilReadSlave,
         appWriteMaster => axilWriteMaster,
         appWriteSlave  => axilWriteSlave,
         --------------
         --  Core Ports
         --------------   
         -- System Ports
         emcClk         => emcClk,
         userClkP       => userClkP,
         userClkN       => userClkN,
         -- QSFP[0] Ports
         qsfp0RstL      => qsfp0RstL,
         qsfp0LpMode    => qsfp0LpMode,
         qsfp0ModSelL   => qsfp0ModSelL,
         qsfp0ModPrsL   => qsfp0ModPrsL,
         -- QSFP[1] Ports
         qsfp1RstL      => qsfp1RstL,
         qsfp1LpMode    => qsfp1LpMode,
         qsfp1ModSelL   => qsfp1ModSelL,
         qsfp1ModPrsL   => qsfp1ModPrsL,
         -- Boot Memory Ports 
         flashCsL       => flashCsL,
         flashMosi      => flashMosi,
         flashMiso      => flashMiso,
         flashHoldL     => flashHoldL,
         flashWp        => flashWp,
         -- PCIe Ports 
         pciRstL        => pciRstL,
         pciRefClkP     => pciRefClkP,
         pciRefClkN     => pciRefClkN,
         pciRxP         => pciRxP,
         pciRxN         => pciRxN,
         pciTxP         => pciTxP,
         pciTxN         => pciTxN);

   --------------------
   -- AXI-Lite Crossbar
   --------------------         
   U_XBAR : entity surf.AxiLiteCrossbar
      generic map (
         TPD_G              => TPD_G,
         NUM_SLAVE_SLOTS_G  => 1,
         NUM_MASTER_SLOTS_G => NUM_AXIL_MASTERS_C,
         MASTERS_CONFIG_G   => AXIL_CONFIG_C)
      port map (
         axiClk              => axilClk,
         axiClkRst           => axilRst,
         sAxiWriteMasters(0) => axilWriteMaster,
         sAxiWriteSlaves(0)  => axilWriteSlave,
         sAxiReadMasters(0)  => axilReadMaster,
         sAxiReadSlaves(0)   => axilReadSlave,
         mAxiWriteMasters    => axilWriteMasters,
         mAxiWriteSlaves     => axilWriteSlaves,
         mAxiReadMasters     => axilReadMasters,
         mAxiReadSlaves      => axilReadSlaves);

   U_GpuAsync: entity axi_pcie_core.AxiPcieGpuAsyncCore
      generic map (
         TPD_G             => TPD_G,
         NUM_CHAN_G        => 1,
         DMA_AXIS_CONFIG_G => DMA_AXIS_CONFIG_C)
      port map (
         axilClk          => axilClk,
         axilRst          => axilRst,
         axilReadMaster   => axilReadMasters(2),
         axilReadSlave    => axilReadSlaves(2),
         axilWriteMaster  => axilWriteMasters(2),
         axilWriteSlave   => axilWriteSlaves(2),
         -- AXI Stream Interface (axisClk domain)
         axisClk          => dmaClk,
         axisRst          => dmaRst,
         sAxisMaster      => strObMasters(0),
         sAxisSlave       => strObSlaves(0),
         mAxisMaster      => strIbMasters(0),
         mAxisSlave       => strIbSlaves(0),
         -- AXI4 Interfaces (axiClk domain)
         axiClk           => dmaClk,
         axiRst           => dmaRst,
         axiWriteMaster   => usrWriteMaster,
         axiWriteSlave    => usrWriteSlave,
         axiReadMaster    => usrReadMaster,
         axiReadSlave     => usrReadSlave);

   U_PrbsTx: entity surf.SsiPrbsTx 
      generic map (
         TPD_G                      => TPD_G,
         PRBS_SEED_SIZE_G           => 256,
         GEN_SYNC_FIFO_G            => false,
         MASTER_AXI_PIPE_STAGES_G   => 1,
         MASTER_AXI_STREAM_CONFIG_G => DMA_AXIS_CONFIG_C)
      port map (
         mAxisClk        => dmaClk,
         mAxisRst        => dmaRst,
         mAxisMaster     => strObMasters(0),
         mAxisSlave      => strObSlaves(0),
         locClk          => axilClk,
         locRst          => axilRst,
         axilReadMaster  => axilReadMasters(0),
         axilReadSlave   => axilReadSlaves(0),
         axilWriteMaster => axilWriteMasters(0),
         axilWriteSlave  => axilWriteSlaves(0));
            
   U_PrbsRx: entity surf.SsiPrbsRx 
      generic map (
         TPD_G                     => TPD_G,
         PRBS_SEED_SIZE_G          => 256,
         GEN_SYNC_FIFO_G           => false,
         SLAVE_AXI_PIPE_STAGES_G   => 1,
         SLAVE_AXI_STREAM_CONFIG_G => DMA_AXIS_CONFIG_C)
      port map (
         sAxisClk        => dmaClk,
         sAxisRst        => dmaRst,
         sAxisMaster     => strIbMasters(0),
         sAxisSlave      => strIbSlaves(0),
         axiClk          => axilClk,
         axiRst          => axilRst,
         axiReadMaster   => axilReadMasters(1),
         axiReadSlave    => axilReadSlaves(1),
         axiWriteMaster  => axilWriteMasters(1),
         axiWriteSlave   => axilWriteSlaves(1));
            
end top_level;

