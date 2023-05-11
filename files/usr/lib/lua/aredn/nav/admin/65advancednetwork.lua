local board = aredn.hardware.get_board_type()
if board == "mikrotik,hap-ac2" or board == "mikrotik,hap-ac3" then
    return { href = "advancednetwork", display = "Advanced Network" }
end
