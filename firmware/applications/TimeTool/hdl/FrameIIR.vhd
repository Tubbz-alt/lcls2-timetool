------------------------------------------------------------------------------
-- File       : TimeToolCore.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-12-04
-- Last update: 2017-12-04
-------------------------------------------------------------------------------
-- Description:
-------------------------------------------------------------------------------
-- This file is part of 'axi-pcie-core'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'axi-pcie-core', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
--use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_signed.all;
use ieee.numeric_std.ALL;

use work.StdRtlPkg.all;
use work.AxiLitePkg.all;
use work.AxiStreamPkg.all;
use work.AxiPkg.all;
use work.SsiPkg.all;
use work.AxiPciePkg.all;
use work.TimingPkg.all;
use work.Pgp2bPkg.all;

library unisim;
use unisim.vcomponents.all;

-------------------------------------------------------------------------------
-- This file performs the the prescaling, or the amount of raw data which is stored
-------------------------------------------------------------------------------

entity FrameIIR is
   generic (
      TPD_G             : time                := 1 ns;
      DMA_AXIS_CONFIG_G : AxiStreamConfigType := ssiAxiStreamConfig(16, TKEEP_COMP_C, TUSER_FIRST_LAST_C, 8, 2);
      DEBUG_G           : boolean             := true );
   port (
      -- System Interface
      sysClk          : in    sl;
      sysRst          : in    sl;
      -- DMA Interfaces  (sysClk domain)
      dataInMaster    : in    AxiStreamMasterType;
      dataInSlave     : out   AxiStreamSlaveType;
      dataOutMaster   : out   AxiStreamMasterType;
      dataOutSlave    : in    AxiStreamSlaveType;
      -- AXI-Lite Interface
      axilReadMaster  : in    AxiLiteReadMasterType;
      axilReadSlave   : out   AxiLiteReadSlaveType;
      axilWriteMaster : in    AxiLiteWriteMasterType;
      axilWriteSlave  : out   AxiLiteWriteSlaveType);
end FrameIIR;

architecture mapping of FrameIIR is

   constant INT_CONFIG_C                  : AxiStreamConfigType := ssiAxiStreamConfig(dataBytes=>16,tDestBits=>0);
   constant PGP2BTXIN_LEN                 : integer             := 19;
   constant CAMERA_RESOLUTION_BITS        : positive            := 8;
   constant CAMERA_PIXEL_NUMBER           : positive            := 2048;

   --type CameraFrameBuffer is array (natural range<>) of slv(CAMERA_RESOLUTION_BITS-1 downto 0);
   type CameraFrameBuffer is array (natural range<>) of signed((CAMERA_RESOLUTION_BITS-1) downto 0);

   type StateType is (
      IDLE_S,
      UPDATE_AND_MOVE_S);

   type RegType is record
      master          : AxiStreamMasterType;
      slave           : AxiStreamSlaveType;
      axilReadSlave   : AxiLiteReadSlaveType;
      axilWriteSlave  : AxiLiteWriteSlaveType;
      counter         : natural range 0 to (CAMERA_PIXEL_NUMBER-1);
      prescalingRate  : slv(31 downto 0);
      axi_test        : slv(31 downto 0);
      state           : StateType;
      rollingImage    : CameraFrameBuffer((CAMERA_PIXEL_NUMBER-1) downto 0);
   end record RegType;

   constant REG_INIT_C : RegType := (
      master          => AXI_STREAM_MASTER_INIT_C,
      slave           => AXI_STREAM_SLAVE_INIT_C,
      axilReadSlave   => AXI_LITE_READ_SLAVE_INIT_C,
      axilWriteSlave  => AXI_LITE_WRITE_SLAVE_INIT_C,
      counter         => 0,
      prescalingRate  => (others=>'0'),
      axi_test        => (others=>'0'),
      state           => IDLE_S,
      rollingImage    => (others => (others => '0') ) );

---------------------------------------
-------record intitial value-----------
---------------------------------------


   signal r             : RegType     := REG_INIT_C;
   signal rin           : RegType     := REG_INIT_C;

   signal inMaster      : AxiStreamMasterType   :=    AXI_STREAM_MASTER_INIT_C;
   signal inSlave       : AxiStreamSlaveType    :=    AXI_STREAM_SLAVE_INIT_C;  
   signal outCtrl       : AxiStreamCtrlType     :=    AXI_STREAM_CTRL_INIT_C;

begin

   ---------------------------------
   -- Input FIFO
   ---------------------------------
   U_InFifo: entity work.AxiStreamFifoV2
      generic map (
         TPD_G               => TPD_G,
         SLAVE_READY_EN_G    => true,
         GEN_SYNC_FIFO_G     => true,
         FIFO_ADDR_WIDTH_G   => 9,
         FIFO_PAUSE_THRESH_G => 500,
         SLAVE_AXI_CONFIG_G  => DMA_AXIS_CONFIG_G,
         MASTER_AXI_CONFIG_G => INT_CONFIG_C)
      port map (
         sAxisClk    => sysClk,
         sAxisRst    => sysRst,
         sAxisMaster => dataInMaster,
         sAxisSlave  => dataInSlave,
         mAxisClk    => sysClk,
         mAxisRst    => sysRst,
         mAxisMaster => inMaster,
         mAxisSlave  => inSlave);


   ---------------------------------
   -- Application
   ---------------------------------
   comb : process (r, sysRst, axilReadMaster, axilWriteMaster, inMaster, outCtrl) is
      variable v      : RegType := REG_INIT_C ;
      variable axilEp : AxiLiteEndpointType;
   begin

      -- Latch the current value
      v := r     ; 

      ------------------------      
      -- AXI-Lite Transactions
      ------------------------      

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave);

      axiSlaveRegister (axilEp, x"00000", 0, v.prescalingRate);
      --axiSlaveRegister (axilEp, x"00000", 8, v.axi_test);

      axiSlaveDefault(axilEp, v.axilWriteSlave, v.axilReadSlave, AXI_RESP_DECERR_C);

      v.slave.tReady    := not outCtrl.pause;
      v.master.tLast    := '0';
      v.master.tValid   := '0';

      case r.state is

            when IDLE_S =>
            ------------------------------
            -- check which state
            ------------------------------
            if v.slave.tReady = '1' and inMaster.tValid = '1' then
                        v.state     := UPDATE_AND_MOVE_S;
               

            else
                  v.slave.tReady    :='0';
                  v.state           := IDLE_S;
            end if;

           
            when UPDATE_AND_MOVE_S  => 
            ------------------------------
            -- update slv logic array
            ------------------------------

               if v.slave.tReady = '1' and inMaster.tValid = '1' then
                  v.master                   := inMaster;     --copies one 'transfer' (trasnfer is the AXI jargon for one TVALID/TREADY transaction)

                  for i in 0 to INT_CONFIG_C.TDATA_BYTES_C-1 loop
                        --v.rollingImage(v.counter + i)             := signed(inMaster.tdata(i*8+7 downto i*8));                    --debug test for getting indices right


                        v.rollingImage(v.counter + i)             := RESIZE((v.rollingImage(v.counter + i)*7+signed(inMaster.tdata(i*8+7 downto i*8)))/8,8);
                        v.master.tData(i*8+7 downto i*8)          := std_logic_vector(v.rollingImage(v.counter + i));                       --output 

                        --v.rollingImage(v.counter)  := (v.rollingImage(v.counter)/32)*31 + signed(inMaster.tdata)/32;
                        --v.master.tData             := std_logic_vector(v.rollingImage(v.counter));
                        --v.rollingImage(v.counter + i*8+7 downto v.counter + i*8 )  := ((v.rollingImage(v.counter + i*8+7 downto v.counter + i*8 ))/32)*31; --+ signed(inMaster.tdata(i*8+7 downto i*8))/32;
                        --v.rollingImage(v.counter + i )     := to_signed(v.counter,8);
                        
                        --v.master.tData(i*8+7 downto i*8)        := std_logic_vector(v.rollingImage(v.counter + i*8+7 downto v.counter + i*8 ));

                  end loop;

                 
                  v.counter                  := v.counter+INT_CONFIG_C.TDATA_BYTES_C;
                  v.state                    := UPDATE_AND_MOVE_S;                  

                  if v.master.tLast = '1' then
                        v.counter            := 0;
                  end if;
                  
                  v.state     := UPDATE_AND_MOVE_S;

               else
                  v.master.tValid  := '0';   --message to downstream data processing that there's no valid data ready
                  v.slave.tReady   := '0';   --message to upstream that we're not ready
                  v.master.tLast   := '0';
                  v.state          := IDLE_S;
               end if;     

      end case;

      -------------
      -- Reset
      -------------
      if (sysRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

      -- Outputs 
      axilReadSlave  <= r.axilReadSlave;
      axilWriteSlave <= r.axilWriteSlave;
      inSlave        <= v.slave;

   end process comb;

   seq : process (sysClk) is
   begin
      if (rising_edge(sysClk)) then
         r <= rin after TPD_G;
      end if;
   end process seq;

   ---------------------------------
   -- Output FIFO
   ---------------------------------
   U_OutFifo: entity work.AxiStreamFifoV2
      generic map (
         TPD_G               => TPD_G,
         SLAVE_READY_EN_G    => false,
         GEN_SYNC_FIFO_G     => true,
         FIFO_ADDR_WIDTH_G   => 9,
         FIFO_PAUSE_THRESH_G => 500,
         SLAVE_AXI_CONFIG_G  => INT_CONFIG_C,
         MASTER_AXI_CONFIG_G => DMA_AXIS_CONFIG_G)
      port map (
         sAxisClk    => sysClk,
         sAxisRst    => sysRst,
         sAxisMaster => r.Master,
         sAxisCtrl   => outCtrl,
         mAxisClk    => sysClk,
         mAxisRst    => sysRst,
         mAxisMaster => dataOutMaster,
         mAxisSlave  => dataOutSlave);

end mapping;
