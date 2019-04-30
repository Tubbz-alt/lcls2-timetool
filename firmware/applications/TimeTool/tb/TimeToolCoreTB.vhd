-------------------------------------------------------------------------------
-- File       : TimeToolKcu1500.vhd
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

use work.StdRtlPkg.all;
use work.AxiPkg.all;
use work.AxiLitePkg.all;
use work.AxiStreamPkg.all;
use work.AxiPciePkg.all;
use work.TimingPkg.all;
use work.Pgp2bPkg.all;
use work.SsiPkg.all;
use work.TestingPkg.all;

use STD.textio.all;
use ieee.std_logic_textio.all;

entity TBPrescaledIIRSubtraction is end TBPrescaledIIRSubtraction;

architecture testbed of TBPrescaledIIRSubtraction is

   constant TEST_OUTPUT_FILE_NAME : string := TEST_FILE_PATH & "/output_results.dat";

   constant AXI_BASE_ADDR_G   : slv(31 downto 0) := x"00C0_0000";

   constant TPD_G             : time             := 1 ns;

   constant DMA_SIZE_C        : positive         := 1;

   constant NUM_MASTERS_G     : positive         := 3;

   ----------------------------
   ----------------------------
   ----------------------------
   constant NUM_AXIL_MASTERS_C  : natural := 4;

   constant PRESCALE_INDEX_C           : natural := 0;
   constant NULL_FILTER_INDEX_C        : natural := 1;
   constant FRAME_IIR_INDEX_C          : natural := 2;
   constant FRAME_SUBTRACTOR_INDEX_C   : natural := 3;


   constant NUM_REPEATER_OUTS          : natural := 2;


   subtype AXIL_INDEX_RANGE_C is integer range NUM_AXIL_MASTERS_C-1 downto 0;

   constant AXIL_CONFIG_C  : AxiLiteCrossbarMasterConfigArray(AXIL_INDEX_RANGE_C) := genAxiLiteConfig(NUM_AXIL_MASTERS_C, AXI_BASE_ADDR_G, 20, 16);

 
   ----------------------------
   ----------------------------
   ----------------------------


   constant DMA_AXIS_CONFIG_G : AxiStreamConfigType := ssiAxiStreamConfig(16, TKEEP_COMP_C, TUSER_FIRST_LAST_C, 8, 2);


   constant CLK_PERIOD_G : time := 10 ns;

   constant SRC_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => 4, -- 128 bits
      TDEST_BITS_C  => 0,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_COMP_C,
      TUSER_BITS_C  => 2,
      TUSER_MODE_C  => TUSER_FIRST_LAST_C);

   signal userClk156   : sl;
   signal dmaClk       : sl;
   signal dmaRst       : sl;

   signal appInMaster  : AxiStreamMasterType;
   signal appInSlave   : AxiStreamSlaveType;
   signal appOutMaster : AxiStreamMasterType;
   signal appOutSlave  : AxiStreamSlaveType;

   signal PrescalerToNullFilterMaster  : AxiStreamMasterType;
   signal PrescalerToNullFilterSlave   : AxiStreamSlaveType;

   signal NullFilterToFrameIIRMaster  : AxiStreamMasterType;
   signal NullFilterToFrameIIRSlave   : AxiStreamSlaveType;

   signal FrameIIRToSubtractorMaster  : AxiStreamMasterType;
   signal FrameIIRToSubtractorSlave  : AxiStreamSlaveType;


   signal axilWriteMaster : AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
   signal axilWriteSlave  : AxiLiteWriteSlaveType  := AXI_LITE_WRITE_SLAVE_INIT_C;
   signal axilReadMaster  : AxiLiteReadMasterType  := AXI_LITE_READ_MASTER_INIT_C;
   signal axilReadSlave   : AxiLiteReadSlaveType   := AXI_LITE_READ_SLAVE_INIT_C;

   signal axilWriteMasters : AxiLiteWriteMasterArray(AXIL_INDEX_RANGE_C);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(AXIL_INDEX_RANGE_C);
   signal axilReadMasters  : AxiLiteReadMasterArray(AXIL_INDEX_RANGE_C);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(AXIL_INDEX_RANGE_C);

   subtype REPEATER_INDEX_RANGE_C is integer range NUM_REPEATER_OUTS-1 downto 0;

   signal dataInMasters : AxiStreamMasterArray(REPEATER_INDEX_RANGE_C);
   signal dataInSlaves  : AxiStreamSlaveArray(REPEATER_INDEX_RANGE_C);

   signal dataIbMasters : AxiStreamMasterArray(REPEATER_INDEX_RANGE_C);
   signal dataIbSlaves  : AxiStreamSlaveArray(REPEATER_INDEX_RANGE_C);

   signal axiClk   : sl;
   signal axiRst   : sl;

   signal axilClk   : sl;
   signal axilRst   : sl;

   file file_RESULTS : text;

begin

   appOutSlave.tReady <= '1';
   appInSlave.tReady  <= '1';
   axilClk            <= axiClk;
   axilRst            <= axiRst;
   
   --------------------
   -- AXI-Lite Crossbar
   --------------------
   U_XBAR : entity work.AxiLiteCrossbar
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

   --------------------
   -- Clocks and Resets
   --------------------
   U_axilClk_2 : entity work.ClkRst
      generic map (
         CLK_PERIOD_G      => CLK_PERIOD_G,
         RST_START_DELAY_G => 0 ns,
         RST_HOLD_TIME_G   => 1000 ns)
      port map (
         clkP => dmaClk,
         rst  => dmaRst);


   --------------------
   -- Clocks and Resets
   --------------------
   U_axilClk : entity work.ClkRst
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

      --U_CamOutput : entity work.AxiStreamCameraOutput
      U_CamOutput : entity work.FileToAxiStreamSim
         generic map (
            TPD_G         => TPD_G,
            BYTE_SIZE_C   => 2+1,
            AXIS_CONFIG_G => SRC_CONFIG_C)
         port map (
            axiClk      => axiClk,
            axiRst      => axiRst,
            mAxisMaster => appInMaster,
            mAxisSlave  => appInSlave);

   -----------------
   -- Time Tool Core
   -----------------
   U_TimeToolCore : entity work.TimeToolCore
      generic map (
         TPD_G           => TPD_G,
         AXI_BASE_ADDR_G => AXI_BASE_ADDR_G)
      port map (
         -- System Clock and Reset
         axilClk         => axiClk,
         axilRst         => axiRst,
         -- Trigger Event streams (axilClk domain)
         --trigMaster      => trigMaster,  -- takes too long too simulate
         --trigSlave       => trigSlave,   -- takes too long too simulate
         -- DMA Interface (sysClk domain)
         dataInMaster    => appInMaster,
         dataInSlave     => appInSlave,
         eventMaster     => appOutMaster,
         --eventSlave      => appOutSlave, --this pin can can only be driven once
         -- AXI-Lite Interface (sysClk domain)
         axilReadMaster  => axilReadMaster,
         axilReadSlave   => axilReadSlave,
         axilWriteMaster => axilWriteMaster,
         axilWriteSlave  => axilWriteSlave);


  ---------------------------------
   -- AXI-Lite Register Transactions
   ---------------------------------
   test : process is
      variable debugData : slv(31 downto 0) := (others => '0');
   begin
      debugData := x"1111_1111";
      ------------------------------------------
      -- Wait for the AXI-Lite reset to complete
      ------------------------------------------
      wait until axiRst = '1';
      wait until axiRst = '0';

      axiLiteBusSimWrite (axiClk, axilWriteMaster, axilWriteSlave, x"00C2_0004", x"5", true);  --prescaler
      axiLiteBusSimWrite (axiClk, axilWriteMaster, axilWriteSlave, x"00C1_0004", x"3", true);  --fex add value
      axiLiteBusSimWrite (axiClk, axilWriteMaster, axilWriteSlave, x"00C0_0fd0", x"0", true);  --event builder bypass

   end process test;

   ---------------------------------
   -- save_file
   ---------------------------------
   save_to_file : process is
      variable to_file              : AxiStreamMasterType := AXI_STREAM_MASTER_INIT_C;
      variable v_OLINE              : line; 
      constant c_WIDTH              : natural := 128;
      constant test_data_to_file    : slv(c_WIDTH -1 downto 0) := (others => '0');

   begin

      to_file := appOutMaster;

      file_open(file_RESULTS, TEST_OUTPUT_FILE_NAME, write_mode);

      while true loop

            --write(v_OLINE, appInMaster.tData(c_WIDTH -1 downto 0), right, c_WIDTH);
            write(v_OLINE, appOutMaster.tData(c_WIDTH-1 downto 0), right, c_WIDTH);
            writeline(file_RESULTS, v_OLINE);

            wait for CLK_PERIOD_G;

      end loop;
      
      file_close(file_RESULTS);

   end process save_to_file;

end testbed;