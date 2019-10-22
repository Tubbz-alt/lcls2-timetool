-------------------------------------------------------------------------------
-- File       : TBAxiStreamFifoV2.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-24
-- Last update: 2018-11-08
-------------------------------------------------------------------------------
-- Description: 
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
use surf.AxiPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;

library axi_pcie_core;
use axi_pcie_core.AxiPciePkg.all;

library lcls_timing_core;
use lcls_timing_core.TimingPkg.all;
use surf.Pgp2bPkg.all;
use surf.SsiPkg.all;
use work.TestingPkg.all;

use STD.textio.all;
use ieee.std_logic_textio.all;

entity TBAxiStreamFifoV2 is end TBAxiStreamFifoV2;

architecture testbed of TBAxiStreamFifoV2 is

   constant TEST_OUTPUT_FILE_NAME : string := TEST_FILE_PATH & "/output_results.dat";

   constant AXI_BASE_ADDR_G   : slv(31 downto 0) := x"00C0_0000";

   constant TPD_G             : time             := 1 ns;

   constant DMA_SIZE_C        : positive         := 1;
 
   ----------------------------
   ----------------------------
   ----------------------------


   constant DMA_AXIS_CONFIG_G           : AxiStreamConfigType := ssiAxiStreamConfig(16, TKEEP_COMP_C, TUSER_FIRST_LAST_C, 8, 2);
   constant DMA_AXIS_DOWNSIZED_CONFIG_G : AxiStreamConfigType := ssiAxiStreamConfig(1, TKEEP_COMP_C, TUSER_FIRST_LAST_C, 1, 2);

   constant CLK_PERIOD_G : time := 10 ns;

   constant SRC_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => 4, -- 128 bits
      TDEST_BITS_C  => 0,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_COMP_C,
      TUSER_BITS_C  => 2,
      TUSER_MODE_C  => TUSER_FIRST_LAST_C);

   signal appInMaster                 : AxiStreamMasterType;
   signal appInSlave                  : AxiStreamSlaveType;

   signal appOutMaster                : AxiStreamMasterType;
   signal appOutSlave                 : AxiStreamSlaveType;

   signal downToUpSizeMaster          : AxiStreamMasterType;
   signal downToUpSizeSlave           : AxiStreamSlaveType;

   signal axiClk                      : sl;
   signal axiRst                      : sl;

begin

   --------------------
   -- Clocks and Resets
   --------------------
   U_axilClk : entity surf.ClkRst
      generic map (
         CLK_PERIOD_G      => CLK_PERIOD_G,
         RST_START_DELAY_G => 0 ns,
         RST_HOLD_TIME_G   => 1000 ns)
      port map (
         clkP => axiClk,
         rst  => axiRst);

   --------------------
   -- Test data
   --------------------  

      U_CamOutput : entity work.FileToAxiStream
         generic map (
            TPD_G              => TPD_G,
            BYTE_SIZE_C        => 2+1,
            DMA_AXIS_CONFIG_G  => DMA_AXIS_CONFIG_G,
            CLK_PERIOD_G       => 23 ns)
         port map (
            sysClk         => axiClk,
            sysRst         => axiRst,
            dataOutMaster  => appInMaster,
            dataOutSlave   => appInSlave);

      U_down_size_test : entity surf.AxiStreamFifoV2
         generic map (
            -- General Configurations
            TPD_G               => TPD_G,
            SLAVE_READY_EN_G    => true,
            VALID_THOLD_G       => 1,
            -- FIFO configurations
            BRAM_EN_G           => true,
            GEN_SYNC_FIFO_G     => true,
            FIFO_ADDR_WIDTH_G   => 9,
            FIFO_PAUSE_THRESH_G => 500,
            -- AXI Stream Port Configurations
            SLAVE_AXI_CONFIG_G  => DMA_AXIS_CONFIG_G,
            MASTER_AXI_CONFIG_G => DMA_AXIS_DOWNSIZED_CONFIG_G)
         port map (
            -- Slave Port
            sAxisClk    => axiClk,
            sAxisRst    => axiRst,
            sAxisMaster => appInMaster,
            sAxisSlave  => appInSlave,
            -- Master Port
            mAxisClk    => axiClk,
            mAxisRst    => axiRst,
            mAxisMaster => downToUpSizeMaster,
            mAxisSlave  => downToUpSizeSlave);

      U_up_size_test : entity surf.AxiStreamFifoV2
         generic map (
            -- General Configurations
            TPD_G               => TPD_G,
            SLAVE_READY_EN_G    => true,
            VALID_THOLD_G       => 1,
            -- FIFO configurations
            BRAM_EN_G           => true,
            GEN_SYNC_FIFO_G     => true,
            FIFO_ADDR_WIDTH_G   => 9,
            FIFO_PAUSE_THRESH_G => 500,
            -- AXI Stream Port Configurations
            SLAVE_AXI_CONFIG_G  => DMA_AXIS_DOWNSIZED_CONFIG_G,
            MASTER_AXI_CONFIG_G => DMA_AXIS_CONFIG_G)
         port map (
            -- Slave Port
            sAxisClk    => axiClk,
            sAxisRst    => axiRst,
            sAxisMaster => downToUpSizeMaster,
            sAxisSlave  => downToUpSizeSlave,
            -- Master Port
            mAxisClk    => axiClk,
            mAxisRst    => axiRst,
            mAxisMaster => appOutMaster,
            mAxisSlave  => appOutSlave);


      U_FileInput : entity work.AxiStreamToFile
         generic map (
            TPD_G              => TPD_G,
            BYTE_SIZE_C        => 2+1,
            DMA_AXIS_CONFIG_G  => DMA_AXIS_CONFIG_G,
            CLK_PERIOD_G       => 24 ns)
         port map (
            sysClk         => axiClk,
            sysRst         => axiRst,
            dataInMaster   => appOutMaster,
            dataInSlave    => appOutSlave);

end testbed;
