//-----------------------------------------------------------------------------
//  (c) Copyright 2011 Xilinx, Inc. All rights reserved.
//
//  This file contains confidential and proprietary information
//  of Xilinx, Inc. and is protected under U.S. and
//  international copyright and other intellectual property
//  laws.
//
//  DISCLAIMER
//  This disclaimer is not a license and does not grant any
//  rights to the materials distributed herewith. Except as
//  otherwise provided in a valid license issued to you by
//  Xilinx, and to the maximum extent permitted by applicable
//  law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
//  WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
//  AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
//  BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
//  INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
//  (2) Xilinx shall not be liable (whether in contract or tort,
//  including negligence, or under any other theory of
//  liability) for any loss or damage of any kind or nature
//  related to, arising under or in connection with these
//  materials, including for any direct, or any indirect,
//  special, incidental, or consequential loss or damage
//  (including loss of data, profits, goodwill, or any type of
//  loss or damage suffered as a result of any action brought
//  by a third party) even if such damage or loss was
//  reasonably foreseeable or Xilinx had been advised of the
//  possibility of the same.
//
//  CRITICAL APPLICATIONS
//  Xilinx products are not designed or intended to be fail-
//  safe, or for use in any application requiring fail-safe
//  performance, such as life-support or safety devices or
//  systems, Class III medical devices, nuclear facilities,
//  applications related to the deployment of airbags, or any
//  other applications that could lead to death, personal
//  injury, or severe property or environmental damage
//  (individually and collectively, "Critical
//  Applications"). Customer assumes the sole risk and
//  liability of any use of Xilinx products in Critical
//  Applications, subject only to applicable laws and
//  regulations governing limitations on product liability.
//
//  THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
//  PART OF THIS FILE AT ALL TIMES.
//-----------------------------------------------------------------------------
// Purpose : Smoke test program for bit accurate C model

#include <stdio.h>
#include "fir_compiler_v7_2_bitacc_cmodel.h"

//---------------------------------------------------------------------------------------------------------------------
// Example message handler
static void msg_print(void* handle, int error, const char* msg)
{
  printf("%s\n",msg);
}

//---------------------------------------------------------------------------------------------------------------------
//Print a xip_array_real
void print_array_real(const xip_array_real* x)
{
  putchar('[');
  if (x && x->data && x->data_size)
  {
    const xip_real* p=x->data;
    const xip_real* q=x->data;
    const xip_real* r=x->data+x->data_size;
    while (q!=r)
    {
      if (q!=p) putchar(' ');
      printf("%g",*q);
      q++;
    }
  }
  putchar(']');
  putchar('\n');
}
//---------------------------------------------------------------------------------------------------------------------
// Print a xip_array_complex
void print_array_complex(const xip_array_complex* x)
{
  putchar('[');
  if (x && x->data && x->data_size)
  {
    const xip_complex* p=x->data;
    const xip_complex* q=x->data;
    const xip_complex* r=x->data+x->data_size;
    while (q!=r)
    {
      if (q!=p) putchar(' ');
           if (!q->re    ) printf("%gi"   ,q->im      );  // Bi
      else if ( q->im<0.0) printf("%g%gi" ,q->re,q->im);  // A-Bi
      else if ( q->im>0.0) printf("%g+%gi",q->re,q->im);  // A+Bi
      else                 printf("%g"    ,q->re      );  // A
      q++;
    }
  }
  putchar(']');
  putchar('\n');
}
//---------------------------------------------------------------------------------------------------------------------
// Print a xip_array_mpz
void print_array_mpz(const xip_array_mpz* x)
{
  putchar('[');
  if (x && x->data && x->data_size)
  {
    int i;
    for(i=0;i<x->data_size;i++) {
      if (i!=x->data_size+1) putchar(' ');
      mpz_out_str(0,10,x->data[i]);
    }
  }
  putchar(']');
  putchar('\n');
}
//---------------------------------------------------------------------------------------------------------------------
// Print a xip_array_mpz_complex
void print_array_mpz_complex(const xip_array_mpz_complex* x)
{
  putchar('[');
  if (x && x->data && x->data_size)
  {
    const xip_mpz_complex* p=x->data;
    const xip_mpz_complex* q=x->data;
    const xip_mpz_complex* r=x->data+x->data_size;
    while (q!=r)
    {
      if (q!=p) putchar(' ');
      if (!q->re    ) {
        mpz_out_str(0,10,q->im);
        printf("i");
      }
      else if ( mpz_sgn(q->im)<0.0) {
        mpz_out_str(0,10,q->re);
        mpz_out_str(0,10,q->im);
        printf("i");
      }
      else if ( mpz_sgn(q->im)>0.0) {
        mpz_out_str(0,10,q->re);
        printf("+");
        mpz_out_str(0,10,q->im);
        printf("i");
      }
      else
        mpz_out_str(0,10,q->re);
      q++;
    }
  }
  putchar(']');
  putchar('\n');
}

//----------------------------------------------------------------------------------------------------------------------
// Fill data array with a scaled impulse. Assumes 3-D array.
int create_impulse(xip_array_real* x) {
  int path;
  int chan;
  int i;
  for (path = 0; path < x->dim[0];path++) {
    for (chan = 0; chan < x->dim[1];chan++) {
       //xip_fir_v7_2_xip_array_real_set_chan(x,(double)((path+1)*(chan+1)),path,chan,0,P_BASIC);
       xip_fir_v7_2_xip_array_real_set_chan(x,(double)(2),path,chan,0,P_BASIC);
       for (i = 1; i < x->dim[2];i++) {
         xip_fir_v7_2_xip_array_real_set_chan(x,0,path,chan,i,P_BASIC);
       }
    }
  }
  return 0;
}

//----------------------------------------------------------------------------------------------------------------------
// String arrays used by the print_config funtion
const char *filt_desc[5] = { "SINGLE RATE", "INTERPOLATION", "DECIMATION", "HILBERT", "INTERPOLATED" };
const char *seq_desc[2] = { "Basic" , "Advanced" };

//----------------------------------------------------------------------------------------------------------------------
// Print a summary of a filter configuration
int print_config(const xip_fir_v7_2_config* cfg) {
  printf("Configuration of %s:\n",cfg->name);
  printf("\tFilter       : ");
  if ( cfg->filter_type == XIP_FIR_SINGLE_RATE || cfg->filter_type == XIP_FIR_HILBERT ) {
    printf("%s\n",filt_desc[cfg->filter_type]);
  } else if ( cfg->filter_type == XIP_FIR_INTERPOLATED ) {
    printf("%s by %d\n",filt_desc[cfg->filter_type],cfg->zero_pack_factor);
  } else {
    printf("%s up by %d down by %d\n",filt_desc[cfg->filter_type],cfg->interp_rate,cfg->decim_rate);
  }
  printf("\tCoefficients : %d ",cfg->coeff_sets);
  if ( cfg->is_halfband ) {
    printf("Halfband ");
  }
  if (cfg->reloadable) {
    printf("Reloadable ");
  }
  printf("coefficient set(s) of %d taps\n",cfg->num_coeffs);
  printf("\tData         : %d path(s) of %d %s channel(s)\n",cfg->num_paths,cfg->num_channels,seq_desc[cfg->chan_seq]);

  return 0;
}

//----------------------------------------------------------------------------------------------------------------------
int main () {

  const char* ver_str = xip_fir_v7_2_get_version();
  printf("-------------------------------------------------------------------------------\n");
  printf("FIR Compiler C Model version: %s\n",ver_str);

  printf("-------------------------------------------------------------------------------\n");
  printf("Default core....\n");
  printf("-------------------------------------------------------------------------------\n");

  // Define filter configuration
  xip_fir_v7_2_config fir_default_cnfg;
  xip_fir_v7_2_default_config(&fir_default_cnfg);

  const int fir_coeffs_size                  = 6;
  int output_width                           = 13;
  const double fir_coeffs[fir_coeffs_size]   = {1,2,3,4,5,6};
  fir_default_cnfg.coeff                     = &fir_coeffs[0];
  fir_default_cnfg.num_coeffs                = fir_coeffs_size;
  fir_default_cnfg.data_width                = 8;
  fir_default_cnfg.coeff_width               = 8;
  fir_default_cnfg.output_width              = output_width;
  fir_default_cnfg.output_rounding_mode      = XIP_FIR_TRUNCATE_LSBS;
  



  fir_default_cnfg.name          = "fir_default";
  print_config(&fir_default_cnfg);

  //Create filter instances
  xip_fir_v7_2* fir_default = xip_fir_v7_2_create(&fir_default_cnfg,&msg_print,0);
  if (!fir_default) {
    printf("Error creating instance\n",fir_default_cnfg.name);
    return -1;
  } else {
    printf("Created instance\n",fir_default_cnfg.name);
  }

  // Create input data packet
  xip_array_real* din = xip_array_real_create();
  xip_array_real_reserve_dim(din,3);
  din->dim_size = 3; // 3D array
  din->dim[0] = fir_default_cnfg.num_paths;
  din->dim[1] = fir_default_cnfg.num_channels;
  din->dim[2] = fir_default_cnfg.num_coeffs; // vectors in a single packet
  din->data_size = din->dim[0] * din->dim[1] * din->dim[2];
  if (xip_array_real_reserve_data(din,din->data_size) == XIP_STATUS_OK) {
    printf("Reserved data\n");
  } else {
    printf("Unable to reserve data!\n");
    return -1;
  }

  // Create output data packet
  //  - Automatically sized using xip_fir_v7_2_calc_size
  xip_array_real* fir_default_out = xip_array_real_create();
  xip_array_real_reserve_dim(fir_default_out,3);
  fir_default_out->dim_size = 3; // 3D array
  if(xip_fir_v7_2_calc_size(fir_default,din,fir_default_out,0)== XIP_STATUS_OK) {
    printf("Calculated output data size\n");
    if (xip_array_real_reserve_data(fir_default_out,fir_default_out->data_size) == XIP_STATUS_OK) {
      printf("Reserved data\n");
    } else {
      printf("Unable to reserve data!\n");
      return -1;
    }
  } else {
    printf("Unable to calculate output date size\n");
    return -1;
  }

  // Populate data in with an impulse
  printf("Create impulse\n");
  create_impulse(din);

  // Send input data and filter
  if ( xip_fir_v7_2_data_send(fir_default,din)== XIP_STATUS_OK) {
    printf("Sent data     : ");
    print_array_real(din);
  } else {
    printf("Error sending data\n");
    return -1;
  }

  // Retrieve filtered data
  if ( xip_fir_v7_2_data_get(fir_default,fir_default_out,0)== XIP_STATUS_OK) {
    printf("Fetched result: ");
    print_array_real(fir_default_out);
  } else {
    printf("Error getting data\n");
    return -1;
  }

  printf("\nTest reset....\n");

  // Send the same data but only fetch first half of the output, reset and then repeat but fetch all the data

  if ( xip_fir_v7_2_data_send(fir_default,din)== XIP_STATUS_OK) {
    printf("Sent data     : ");
    print_array_real(din);
  } else {
    printf("Error sending data\n");
    return -1;
  }

  // Create a new output data packet
  xip_array_real* fir_default_out2 = xip_array_real_create();
  xip_array_real_reserve_dim(fir_default_out2,3);
  fir_default_out2->dim_size = 3; // 3D array
  if(xip_fir_v7_2_calc_size(fir_default,din,fir_default_out2,0)== XIP_STATUS_OK) {
    printf("Calculated output data size\n");
    // Reduce output packet to only read half the generated data
    fir_default_out2->dim[2]    = fir_default_out2->dim[2] / 2;
    fir_default_out2->data_size = fir_default_out2->dim[1] * fir_default_out2->dim[1] * fir_default_out2->dim[2];
    if (xip_array_real_reserve_data(fir_default_out2,fir_default_out2->data_size) == XIP_STATUS_OK) {
      printf("Reserved data\n");
    } else {
      printf("Unable to reserve data!\n");
      return -1;
    }
  } else {
    printf("Unable to calculate output date size\n");
    return -1;
  }

  // Get reduced output data packet
  if ( xip_fir_v7_2_data_get(fir_default,fir_default_out2,0)== XIP_STATUS_OK) {
    printf("Fetched result: ");
    print_array_real(fir_default_out2);
  } else {
    printf("Error getting data\n");
    return -1;
  }

  // Apply reset to model
  printf("Apply reset\n");
  if ( xip_fir_v7_2_reset(fir_default) != XIP_STATUS_OK) {
    printf("Error applying reset\n");
    return -1;
  }

  // Try fetching some data
  if ( xip_fir_v7_2_data_get(fir_default,fir_default_out2,0)== XIP_STATUS_OK) {
    if ( fir_default_out2->dim[2] == 0 ) {
      printf("Zero data fetched\n");
    } else {
      printf("Error, fetched result: ");
      print_array_real(fir_default_out2);
      return -1;
    }
  } else {
    printf("Error getting data\n");
    return -1;
  }

  // Send input data again and read output
  if ( xip_fir_v7_2_data_send(fir_default,din)== XIP_STATUS_OK) {
    printf("Sent data     : ");
  } else {
    printf("Error sending data\n");
    return -1;
  }
  print_array_real(din);

  // Read full output packet size
  fir_default_out2->dim[2]    = fir_default_cnfg.num_coeffs;
  fir_default_out2->data_size = fir_default_out2->dim[1] * fir_default_out2->dim[1] * fir_default_out2->dim[2];
  if (xip_array_real_reserve_data(fir_default_out2,fir_default_out2->data_size) == XIP_STATUS_OK) {
    printf("Reserved data\n");
  } else {
    printf("Unable to reserve data!\n");
    return -1;
  }

  if ( xip_fir_v7_2_data_get(fir_default,fir_default_out2,0)== XIP_STATUS_OK) {
    printf("Fetched result: ");
  } else {
    printf("Error getting data\n");
    return -1;
  }
  print_array_real(fir_default_out2);

  //De-allocate data
  xip_array_real_destroy(din);
  xip_array_real_destroy(fir_default_out);
  xip_array_real_destroy(fir_default_out2);

  //De-allocate fir instances
  xip_fir_v7_2_destroy(fir_default);

  printf("...End\n");
}
