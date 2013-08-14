library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.numeric_std.all;


-- A package to store the two main components.
package AUDIO is


--/////////////////////// AC97 Driver //////////////////////////////////--

component ac97 
	port (
		n_reset        : in  std_logic;
		clk            : in  std_logic;
															-- ac97 interface signals
		ac97_sdata_out : out std_logic;						-- ac97 output to SDATA_IN
		ac97_sdata_in  : in  std_logic;						-- ac97 input from SDATA_OUT
		ac97_sync      : out std_logic;						-- SYNC signal to ac97
		ac97_bitclk    : in  std_logic;						-- 12.288 MHz clock from ac97
		ac97_n_reset   : out std_logic;						-- ac97 reset for initialization [active low]
		ac97_ready_sig : out std_logic; 					-- pulse for one cycle
		L_out          : in  std_logic_vector(17 downto 0);	-- lt chan output from ADC
		R_out          : in  std_logic_vector(17 downto 0);	-- rt chan output from ADC
		L_in           : out std_logic_vector(17 downto 0);	-- lt chan input to DAC
		R_in           : out std_logic_vector(17 downto 0);	-- rt chan input to DAC
		cmd_ready  	   : in  std_logic;
		cmd_addr       : in  std_logic_vector(7 downto 0);	-- cmd address coming in from ac97cmd state machine
		cmd_data       : in  std_logic_vector(15 downto 0) 	-- cmd data coming in from ac97cmd state machine
		);
end component;


--/////////////// STATE MACHINE TO CONFIGURE THE AC97 ///////////////////////////--

component ac97cmd 
	port (
		 clk      		: in  std_logic;
		 ready    		: in  std_logic;
		 cmd_addr 		: out std_logic_vector(7 downto 0);
		 cmd_data 		: out std_logic_vector(15 downto 0);
		 cmd_ready 		: out std_logic;
		 volume   		: in  std_logic_vector(4 downto 0);
		 source   		: in  std_logic_vector(2 downto 0)
		 );
end component;



end AUDIO;



-------------------------------------------------------------------------------------
--//////////////////////////// COMPONENTS /////////////////////////////////////////--
-------------------------------------------------------------------------------------


--/////////////////////// AC97 CONTROLLER //////////////////////////////////--

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.numeric_std.all;

entity ac97 is
	port (
		n_reset        : in  std_logic;
		clk            : in  std_logic;
															-- ac97 interface signals
		ac97_sdata_out : out std_logic;						-- ac97 output to SDATA_IN
		ac97_sdata_in  : in  std_logic;						-- ac97 input from SDATA_OUT
		ac97_sync      : out std_logic;						-- SYNC signal to ac97
		ac97_bitclk    : in  std_logic;						-- 12.288 MHz clock from ac97
		ac97_n_reset   : out std_logic;						-- ac97 reset for initialization [active low]
		ac97_ready_sig : out std_logic; 					-- pulse for one cycle
		L_out          : in  std_logic_vector(17 downto 0);	-- lt chan output from ADC
		R_out          : in  std_logic_vector(17 downto 0);	-- rt chan output from ADC
		L_in           : out std_logic_vector(17 downto 0);	-- lt chan input to DAC
		R_in           : out std_logic_vector(17 downto 0);	-- rt chan input to DAC
		cmd_ready   : in  std_logic;
		cmd_addr       : in  std_logic_vector(7 downto 0);	-- cmd address coming in from ac97cmd state machine
		cmd_data       : in  std_logic_vector(15 downto 0));-- cmd data coming in from ac97cmd state machine
end ac97;


architecture arch of ac97 is


	signal Q1, Q2   		: std_logic;					-- signals to deliver one cycle pulse at specified time
	signal bit_count    	: integer range 0 to 255;	-- counter for aligning slots
	signal rst_counter  	: integer range 0 to 4097;		-- counter to set ac97_reset high for ac97 init
								
	signal cmd_adr_buffer   : std_logic_vector(19 downto 0); -- signals to latch in registers and commands
	signal cmd_data_buffer   : std_logic_vector(19 downto 0);

	signal left_data_buffer	: std_logic_vector(19 downto 0);
	signal right_data_buffer : std_logic_vector(19 downto 0);

	signal left_data     	: std_logic_vector(19 downto 0);
	signal right_data    	: std_logic_vector(19 downto 0);
	signal left_in_data  	: std_logic_vector(19 downto 0);
	signal right_in_data 	: std_logic_vector(19 downto 0);
	
  
begin

	
	-------------------------------------------------------------------------------------
	left_data  <= L_out & "00";
	right_data <= R_out & "00";
	L_in <= left_in_data(19 downto 2);
	R_in <= right_in_data(19 downto 2);
	

	
	--------------------------------------------------------------------------------------
	-- CONTROLER RESET
	process (clk)
	begin
	-- Delay for ac97_reset signal, clk = 100MHz
	-- delay 10ns * 37.89 us for active low reset on init
		if rising_edge(clk) then
			if n_reset = '0' then
				rst_counter <= 0;
				ac97_n_reset <= '0';
			elsif rst_counter = 3789 then  
				ac97_n_reset <= '1';
				rst_counter <= 0;
			else
				rst_counter <= rst_counter + 1;
			end if;
		end if;
	end process;
	
	
	-- This process generates a single clkcycle pulse
	-- to get configuration data from the ac97cmd FSM
	-- and lets the user know when a sample is ready
	---------------------------------------------------------------------------------------										
	process (clk)
	begin
		if rising_edge(clk) then
			Q2 <= Q1;
			if(bit_count = 0) then
				Q1 <= '0';
				Q2 <= '0';
			elsif(bit_count >= 129) then
				Q1 <= '1';
			end if;
			ac97_ready_sig <= Q1 and not Q2;
		end if;
	end process;
		
	---------------------------------------------------------------------------------------
	-- BIT COUNTER 
	process (ac97_bitclk)
	begin
	if rising_edge(ac97_bitclk) then 
		if n_reset = '0' then 
			bit_count <= 0;
		else
			bit_count <= bit_count + 1;
		end if;
	end if;
	end process;
	---------------------------------------------------------------------------------------
	-- SYNC GENERATION
	process (ac97_bitclk)
	begin
	if rising_edge(ac97_bitclk) then 
		if bit_count = 255 then 
			ac97_sync <= '1';
		elsif bit_count = 15 then
			ac97_sync <= '0';
		end if;
	end if;
	end process;
	---------------------------------------------------------------------------------------	
	-- OUT DATA
	process (ac97_bitclk)
	begin
		if rising_edge(ac97_bitclk) then	
		
			if bit_count = 255 then
				cmd_adr_buffer   <= cmd_addr & "000000000000";
				cmd_data_buffer   <= cmd_data & "0000";
				left_data_buffer  <= left_data;
				right_data_buffer <= right_data;
			end if;	 
			
			
			-- Slot 0 : Tag Phase bit count 0 to 15																
			if (bit_count >= 0) and (bit_count <= 15) then					
																			
				case bit_count is											
					when 0     		=> ac97_sdata_out <= '1';      				-- AC Link Interface ready
					when 1      	=> ac97_sdata_out <= cmd_ready; 			-- Valid Status Adress or Slot request
					when 2      	=> ac97_sdata_out <= '1';  					-- Valid Status data 
					when 3      	=> ac97_sdata_out <= '1';      				-- Valid PCM Data (Left ADC)
					when 4      	=> ac97_sdata_out <= '1';      				-- Valid PCM Data (Right ADC)
					when others 	=> ac97_sdata_out <= '0';
				end case;
			
			-- Slot 1 : Command address (8-bits, left justified) bit count 16 to 35, add 20 bit counts each time			
			elsif (bit_count >= 16) and (bit_count <= 35) then
			
				if cmd_ready = '1' then
					ac97_sdata_out <= cmd_adr_buffer(35 - bit_count);
				else
					ac97_sdata_out <= '0';
				end if;
				
			-- Slot 2 : Command data (16-bits, left justified) bit count 36 to 55
			elsif (bit_count >= 36) and (bit_count <= 55) then
			
				if cmd_ready = '1' then
					ac97_sdata_out <= cmd_data_buffer(55 - bit_count);
				else
					ac97_sdata_out <= '0';
				end if;
				
			-- Slot 3 : left channel bit count 56 to 75
			elsif ((bit_count >= 56) and (bit_count <= 75)) then
			
				ac97_sdata_out <= left_data_buffer(19);	
				left_data_buffer <= left_data_buffer(18 downto 0) & left_data_buffer(19);
				
			-- Slot 4 : right channel bit count 76 to 95
			elsif ((bit_count >= 76) and (bit_count <= 95)) then	
				ac97_sdata_out <= right_data_buffer(95 - bit_count);
			else
				ac97_sdata_out <= '0';
			end if;
		end if;
	end process;

	
	---------------------------------------------------------------------------
	-- IN DATA
	process (ac97_bitclk)
	begin
		if rising_edge(ac97_bitclk) then						-- clock on falling edge of bitclk
		
		-- Slot 3 : left channel from 57 to 76
			if (bit_count >= 57) and (bit_count <= 76) then 	
			
				left_in_data <= left_in_data(18 downto 0) & ac97_sdata_in;		-- concat incoming bits on end
				
		-- Slot 4 : right channel from 77 to 96		
			elsif (bit_count >= 77) and (bit_count <= 96) then 
			
				right_in_data <= right_in_data(18 downto 0) & ac97_sdata_in;	-- concat incoming bits on end
			end if;
		end if;
	end process;

end arch;



--/////////////// STATE MACHINE TO CONFIGURE THE AC97 ///////////////////////////--

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.numeric_std.all;


entity ac97cmd is
	port (
		 clk      		: in  std_logic;
		 ac97_ready_sig : in  std_logic;
		 cmd_addr 		: out std_logic_vector(7 downto 0);
		 cmd_data 		: out std_logic_vector(15 downto 0);
		 cmd_ready	: out std_logic;
		 volume   		: in  std_logic_vector(4 downto 0);  -- input for encoder for volume control 0->31
		 source   		: in  std_logic_vector(2 downto 0)); -- 000=Mic, 100=LineIn
end ac97cmd;


architecture arch of ac97cmd is
	signal cmd		: std_logic_vector(23 downto 0);  
	signal atten	: std_logic_vector(4 downto 0);							-- used to set atn in 04h ML4:0/MR4:0
	type state_type is (S0, S1, S2, S3, S4, S5, S6, S7, S8, S9, S10, S11);
	signal cur_state, next_state : state_type;
begin
																			-- parse command from data
   cmd_addr <= cmd(23 downto 16);
   cmd_data <= cmd(15 downto 0);
   atten    <= std_logic_vector(31 - unsigned(volume));      				-- convert vol to attenuation

	-- USED TO DETERMINE IF THE REGISTER ADDRESS IS VALID 
	-- one can add more with select statments with output signals to do more error checking
	---------------------------------------------------------------------------------------------
	with cmd(23 downto 16) select
		cmd_ready <=
			'1' when X"02" | X"04" | X"06" | X"0A" | X"0C" | X"0E" | X"10" | X"12" | X"14" | 
					 X"16" | X"18" | X"1A" | X"1C" | X"20" | X"22" | X"24" | X"26" | X"28" | 
					 X"2A" | X"2C" | X"32" | X"5A" | X"74" | X"7A" | X"7C" | X"7E" | X"80",
			'0' when others;
			
	
	-- go through states based on input pulses from ac97 ready signal
	------------------------------------------------------------------------------------------
	process(clk)
		begin
																
		if rising_edge(clk) then
			if ac97_ready_sig = '1' then
				cur_state <= next_state;
			end if;
		end if;
	end process;
	
		
	-- use state machine to configure controller
	-- refer to register map on LM4550 data sheet 
	-- signals and input busses can be added to control the AC97 codec refer to the source and volume to see how
	-- first part is address, second part after _ is command
	-- states and input signals can be added for real time configuration of 
	-- any ac97 register
	-------------------------------------------------------------------------------------------
	process (next_state, cur_state, atten, source)
	begin

		case cur_state is
			when S0 =>
				cmd <= X"02_8000";  -- master volume	0 0000->0dB atten, 1 1111->46.5dB atten								
				next_state <= S2;
			when S1 => 
				cmd <= X"04" & "000" & atten & "000" & atten;	-- headphone volume
				next_state <= S4;
			when S2 => 
				cmd <= X"0A_0000";  							-- Set pc_beep volume
				next_state <= S11;
			when S3 => 
				cmd <= X"0E_8048";  							-- Mic Volume set to gain of +20db
				next_state <= S10;
			when S4 => 
				cmd <= X"18_0808";  							-- PCM volume
				next_state <= S6;
			when S5 =>
				cmd <= X"1A" & "00000" & source & "00000" & source; -- Record select reg 000->Mic, 001->CD in l/r, 010->Video in l/r, 011->aux in l/r
				next_state <= S7;		-- 100->line_in l/r, 101->stereo mix, 110->mono mix, 111->phone input
			when S6 =>
				cmd <= X"1C_0F0F";  	-- Record gain set to max (22.5dB gain)
				next_state <= S8;	
			when S7 =>
				cmd <= X"20_8000";  	-- PCM out path 3D audio bypassed
				next_state <= S0;
			when S8 => 
				cmd <= X"2C_BB80";   	-- DAC rate 48 KHz,	can be set to 1F40 = 8Khz, 2B11 = 11.025KHz, 3E80 = 16KHz,											 
				next_state <= S5;		-- 5622 = 22.05KHz, AC44 = 44.1KHz, BB80 = 48KHz
			when S9 =>
				cmd <= X"32_BB80";  	-- ADC rate 48 KHz,	can be set to 1F40 = 8Khz, 2B11 = 11.025KHz, 3E80 = 16KHz,									 
				next_state <= S3;		-- 5622 = 22.05KHz, AC44 = 44.1KHz, BB80 = 48KHz	
			when S10 =>
				cmd <= X"80_0000";  							  					
				next_state <= S9;
			when S11 =>
				cmd <= X"80_0000";  												
				next_state <= S1;
			end case;
	 
  end process;

end arch;







