

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;
use work.AUDIO.all;	


entity Top_level is
		Port ( 	clk 		: in  STD_LOGIC;
				n_reset 	: in  STD_LOGIC;
				SDATA_IN 	: in STD_LOGIC;
				BIT_CLK 	: in STD_LOGIC;
				SOURCE 		: in STD_LOGIC_VECTOR(2 downto 0);
				VOLUME_UP 	: in std_LOGIC;
				VOLUME_DOWN : in std_LOGIC;
				SYNC 		: out STD_LOGIC;
				SDATA_OUT 	: out STD_LOGIC;
				AC97_n_RESET : out STD_LOGIC
			  );
end Top_level;


architecture arch of Top_level is

	signal L_bus, R_bus, L_bus_out, R_bus_out : std_logic_vector(17 downto 0);	
	signal cmd_addr : std_logic_vector(7 downto 0);
	signal cmd_data : std_logic_vector(15 downto 0);
	signal ready : std_logic;
	signal cmd_ready : std_logic;
	signal volume : std_logic_vector(4 downto 0):="00000";
	signal volume_pushbutton_pre_state : std_logic:='0';
	


begin
		
	
	ac97_cont0 : entity work.ac97(arch)
		port map(n_reset => n_reset,
				clk => clk,
				ac97_sdata_out	 	=> SDATA_OUT, 
				ac97_sdata_in 		=> SDATA_IN, 
				cmd_ready 		    => cmd_ready,
				ac97_sync 			=> SYNC, 
				ac97_bitclk 		=> BIT_CLK, 
				ac97_n_reset 		=> AC97_n_RESET, 
				ac97_ready_sig 		=> ready,
				L_out 				=> L_bus, 
				R_out 				=> R_bus, 
				L_in 				=> L_bus_out,
				R_in 				=> R_bus_out, 
				cmd_addr	 		=> cmd_addr, 
				cmd_data 			=> cmd_data);
 
   ac97cmd_cont0 : entity work.ac97cmd(arch)
	   port map (clk => clk, 
				ac97_ready_sig => ready, 
				cmd_addr => cmd_addr,
				cmd_data => cmd_data, 
				volume => volume, 
				source => SOURCE, 
				cmd_ready => cmd_ready);  

	
	-------------------------------------------------------------------------------
	-- VOLUME 
	-- The volume is coded on 5 bit = 32 so 4*8 = 32, it takes 8 clicks to go from min to max volume
	process (clk)
	
	begin
	if rising_edge(clk) then 
		if VOLUME_UP = '1' and volume_pushbutton_pre_state = '0' then 
			--volume <= volume(3 downto 0) & '0';
			if volume /= "11111" then 
				volume <= std_logic_vector(unsigned (volume) + 4);
			end if ;
		elsif VOLUME_DOWN = '1' and volume_pushbutton_pre_state = '0' then 
			--volume <= '0' & volume(4 downto 1);
			if volume /= "00000" then 
				volume <= std_logic_vector(unsigned (volume) - 4);
			end if ;
		end if;
		volume_pushbutton_pre_state <= VOLUME_UP or VOLUME_DOWN;
			
	end if;	
	end process;
	
	-- TALK TROUGHT
	process ( clk, n_reset, L_bus_out, R_bus_out)
  
	begin		
		if rising_edge(clk) then
			if n_reset = '0' then
				L_bus <= (others => '0');
				R_bus <= (others => '0');
			elsif(ready = '1') then
				L_bus <= L_bus_out;
				R_bus <= R_bus_out;
			end if;
		end if;
	end process;
	

end arch;
