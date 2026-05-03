import cocotb
import random
import Crypto
from cocotb.clock import Clock
from cocotb.triggers import (
    RisingEdge,
    FallingEdge,
    Timer,
    ClockCycles,
    ReadOnly
)
from cocotb.simtime import get_sim_time
from Crypto.Hash import SHA256
from Crypto.Random import get_random_bytes
from Crypto.Cipher import AES

# =========================
# Dedicated inputs: ui_in
# =========================
UI_SCLK = 1 << 0   # ui_in[0]  SPI clock from HOST
UI_N_CS = 1 << 1   # ui_in[1]  active-low SPI CS from HOST
UI_MOSI = 1 << 2   # ui_in[2]  SPI MOSI from HOST


# =========================
# Dedicated outputs: uo_out
# =========================
UO_MISO     = 1 << 0   # uo_out[0]  SPI MISO to HOST
UO_SCLK_MEM = 1 << 1   # uo_out[1]  SPI clock to MEM
UO_N_CS_MEM = 1 << 2   # uo_out[2]  active-low SPI CS to MEM


# =========================
# Bidirectional memory inputs: uio_in
# =========================
UIO_IN_MEM_QSPI_0 = 1 << 0   # uio_in[0]
UIO_IN_MEM_QSPI_1 = 1 << 1   # uio_in[1]
UIO_IN_MEM_QSPI_2 = 1 << 2   # uio_in[2]
UIO_IN_MEM_QSPI_3 = 1 << 3   # uio_in[3]


# =========================
# Bidirectional memory outputs: uio_out
# =========================
UIO_OUT_MEM_QSPI_0 = 1 << 0   # uio_out[0]
UIO_OUT_MEM_QSPI_1 = 1 << 1   # uio_out[1]
UIO_OUT_MEM_QSPI_2 = 1 << 2   # uio_out[2]
UIO_OUT_MEM_QSPI_3 = 1 << 3   # uio_out[3]


# =========================
# Bidirectional output enables: uio_oe
# =========================
UIO_OE_MEM_QSPI_0 = 1 << 0   # uio_oe[0]
UIO_OE_MEM_QSPI_1 = 1 << 1   # uio_oe[1]
UIO_OE_MEM_QSPI_2 = 1 << 2   # uio_oe[2]
UIO_OE_MEM_QSPI_3 = 1 << 3   # uio_oe[3]
"""
cpu to ctrl spi

CPOL = 0    
CPHA = 0
SCLK idle low
MOSI changes on falling edge
DUT samples MOSI on rising edge
MISO changes on falling edge
TB samples MISO on rising edge

"""

"""
mem to flash spi

CPOL = 1
CPHA = 1
SCLK idle high
MOSI changes on falling edge
DUT samples MOSI on rising edge
MISO changes on falling edge
TB samples MISO on rising edge

"""
def get_bit(sig, idx):
    return (int(sig.value) >> idx) & 1

def make_opcode(valid, key_addr, text_addr, dest_addr, encrypt, sha):
    opcode = 0
    opcode |= (valid & 1) << 74
    opcode |= (encrypt & 1) << 73 # 0 is encrypt 1 is decrypt
    opcode |= (sha & 1) << 72 # 1 is sha 0 is aes
    opcode |= (key_addr & 0xFFFFFF) << 48
    opcode |= (text_addr & 0xFFFFFF) << 24
    opcode |= (dest_addr & 0xFFFFFF)
    return opcode

def rand_addr():
    return random.randint(0, 0xFFFFFF)

async def settle():
    await Timer(1, "ns")
    await ReadOnly()

async def reset_dut(dut):
    dut.rst_n.value = 0

    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    dut.ui_in.value = 0
    dut.ui_in.value = UI_N_CS
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 2)

async def wait_bit_low(dut, signal, mask):
    while int(signal.value) & mask:
        await RisingEdge(dut.clk)


async def wait_bit_rise(dut, signal, mask):
    prev = int(signal.value) & mask
    while True:
        await RisingEdge(dut.clk)
        curr = int(signal.value) & mask
        if prev == 0 and curr != 0:
            return
        prev = curr


async def wait_bit_fall(dut, signal, mask):
    prev = int(signal.value) & mask
    while True:
        await RisingEdge(dut.clk)
        curr = int(signal.value) & mask
        if prev != 0 and curr == 0:
            return
        prev = curr


async def get_mem_output_spi(dut, length):
    # wait for mem qspi cs low
    await wait_bit_low(dut, dut.uo_out, UO_N_CS_MEM)
    collected = 0x00

    for _ in range(length):
        # wait for mem qspi sclk rising
        await wait_bit_rise(dut, dut.uo_out, UO_SCLK_MEM)
        # read qspi out bit 0
        bit = 1 if (int(dut.uio_out.value) & UIO_OUT_MEM_QSPI_0) else 0
        collected = (collected << 1) | bit

    t = get_sim_time(unit="ns")
    dut._log.info(f"[{t} ns] {length} bits collected {collected:#x}")

    return collected


def set_mem_io1(dut, bit):
    val = int(dut.uio_in.value)
    if bit:
        val |= UIO_IN_MEM_QSPI_1
    else:
        val &= ~UIO_IN_MEM_QSPI_1
    dut.uio_in.value = val


async def get_mem_output_return_spi(dut, returned):
    # wait for mem qspi cs low
    await wait_bit_fall(dut, dut.uo_out, UO_N_CS_MEM)
    collected = 0x00

    # collect 1 byte from dut
    for _ in range(8):
        # wait for mem qspi sclk rising
        await wait_bit_rise(dut, dut.uo_out, UO_SCLK_MEM)
        # flash sample output on rising edge
        bit = 1 if (int(dut.uio_out.value) & UIO_OUT_MEM_QSPI_0) else 0
        collected = (collected << 1) | bit

    # return 1byte to dut
    for bit_idx in range(7, -1, -1):
        bit = (returned >> bit_idx) & 1
        # flash updates output on falling edge
        await wait_bit_fall(dut, dut.uo_out, UO_SCLK_MEM)
        set_mem_io1(dut, bit)
        # DUT samples this bit on next rising edge
        await wait_bit_rise(dut, dut.uo_out, UO_SCLK_MEM)

    t = get_sim_time(unit="ns")
    dut._log.info(
        f"[{t} ns] collected opcode/data {collected:#04x}, returned {returned:#04x}")
    return collected

async def send_cpu_opcode(dut, opcode):
    # idle cs high, sclk low
    
    dut.ui_in.value = UI_N_CS
    await RisingEdge(dut.clk)
    # pull cs low
    dut.ui_in.value = 0
    await RisingEdge(dut.clk)
    # send 75 bits, msb first
    for bit_idx in range(74, -1, -1):
        bit = (opcode >> bit_idx) & 1
        mosi = UI_MOSI if bit else 0

        # sclk low, set MOSI
        dut.ui_in.value = mosi
        await RisingEdge(dut.clk)

        # dut sample on rising
        dut.ui_in.value = mosi | UI_SCLK
        await RisingEdge(dut.clk)

    # sclk low before ending
    dut.ui_in.value = 0
    await RisingEdge(dut.clk)

    # pull cs high
    dut.ui_in.value = UI_N_CS
    await RisingEdge(dut.clk)

async def read_ack_op(dut):
    ack = 0
    # 25b MSB first
    # idle cs high, sclk low
    dut.ui_in.value = UI_N_CS
    await RisingEdge(dut.clk)

    # pull cs low
    dut.ui_in.value = 0
    await RisingEdge(dut.clk)

    # read 25 bits, msb first
    for bit_idx in range(24, -1, -1):
        # sclk low, MOSI dummy 0
        dut.ui_in.value = 0
        await RisingEdge(dut.clk)

        # dut output sampled on rising
        dut.ui_in.value = UI_SCLK
        await RisingEdge(dut.clk)

        # read MISO
        miso = 1 if (int(dut.uo_out.value) & UO_MISO) else 0
        ack = (ack << 1) | miso

    # sclk low before ending
    dut.ui_in.value = 0
    await RisingEdge(dut.clk)

    # pull cs high
    dut.ui_in.value = UI_N_CS
    await RisingEdge(dut.clk)

    valid = (ack >> 24) & 1
    addr = ack & 0xFFFFFF

    return valid, addr

async def qspi_rd_txt(dut,text,length):
    """read text operation at certain addr"""
    dut.uio_in.value = 0
    # wait for mem qspi cs low
    await wait_bit_low(dut, dut.uo_out, UO_N_CS_MEM)
    collected = 0x00
    addr = 0x000000
    # 8b opc
    for _ in range(8):
    # wait for mem qspi sclk rising
        await wait_bit_rise(dut, dut.uo_out, UO_SCLK_MEM)
        # read qspi out bit 0
        bit = 1 if (int(dut.uio_out.value) & UIO_OUT_MEM_QSPI_0) else 0
        collected = (collected << 1) | bit
    # 24b addr
    for _ in range(24):
        await wait_bit_rise(dut, dut.uo_out, UO_SCLK_MEM)
        # read qspi out bit 0
        bit = 1 if (int(dut.uio_out.value) & UIO_OUT_MEM_QSPI_0) else 0
        addr = (addr << 1) | bit
    #8 dummy
    for _ in range(8):
        # wait for mem qspi sclk rising
        await wait_bit_rise(dut, dut.uo_out, UO_SCLK_MEM)
    # each half byte per cycle
    for i in range(length):
        cur_byte = (text >> (8*(length - 1 - i))) & 0xff 
        for j in range(2):
            # wait for mem qspi sclk fall
            await wait_bit_fall(dut, dut.uo_out, UO_SCLK_MEM)
            cur_half = (cur_byte >> (4*(1-j))) & 0xf 
            dut.uio_in.value = cur_half
            await wait_bit_rise(dut, dut.uo_out, UO_SCLK_MEM)

    dut.uio_in.value = 0

    return collected,addr

async def qspi_wr_txt(dut,length):
    """write text operation at certain addr"""
    # wait for mem qspi cs low
    await wait_bit_low(dut, dut.uo_out, UO_N_CS_MEM)
    collected = 0x00
    addr = 0x000000
    text = 0x00
    # 8b opc
    for _ in range(8):
    # wait for mem qspi sclk rising
        await wait_bit_rise(dut, dut.uo_out, UO_SCLK_MEM)
        # read qspi out bit 0
        bit = 1 if (int(dut.uio_out.value) & UIO_OUT_MEM_QSPI_0) else 0
        collected = (collected << 1) | bit
    # 24b addr
    for _ in range(24):
        await wait_bit_rise(dut, dut.uo_out, UO_SCLK_MEM)
        # read qspi out bit 0
        bit = 1 if (int(dut.uio_out.value) & UIO_OUT_MEM_QSPI_0) else 0
        addr = (addr << 1) | bit
    # each half byte per cycle
    for i in range(length):
        cur_byte = 0
        for j in range(2):
            # wait for mem qspi sclk fall
            await wait_bit_rise(dut, dut.uo_out, UO_SCLK_MEM)
            cur_half = int(dut.uio_out.value) & 0xf
            cur_byte = (cur_half << (4*(1-j))) | cur_byte
        text = (text << 8) | cur_byte

    return collected,addr,text

async def sha_flash_model(dut, text):
    # rd txt
    rd_opc, rd_addr = await qspi_rd_txt(dut, text, 32)

    # wr txt
    wr_opc, wr_addr, output_txt = await qspi_wr_txt(dut, 32)

    return rd_opc, rd_addr, wr_opc, wr_addr, output_txt

async def aes_flash_model(dut, key, text):
    # rd key
    rd_key_opc, rd_key_addr = await qspi_rd_txt(dut, key, 32)

    # rd txt
    rd_txt_opc, rd_txt_addr = await qspi_rd_txt(dut, text, 16)

    # wr txt
    wr_opc, wr_addr, output_txt = await qspi_wr_txt(dut, 16)

    return rd_key_opc, rd_key_addr, rd_txt_opc, rd_txt_addr, wr_opc, wr_addr, output_txt

@cocotb.test()
async def reset_test(dut):

    # 50Mhz clk
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())

    dut._log.info("Reset start")
    await reset_dut(dut)
    dut._log.info("Reset done")
    dut._log.info("Initialization flow start")
    uio_oe = 0b1111 & int(dut.uio_oe.value)
    assert (uio_oe & 0b1100) == 0b1100, f"SPI mode: IO2/3 driven must be high, uio_oe={uio_oe:04b}"
    assert uio_oe == 0b1101, f"uio_oe expected 0b1101 got {uio_oe:#04b}"

    # WREN
    opcode = await get_mem_output_spi(dut,8)
    assert opcode == 0x06, f"Opcode expected 0x06 got {opcode:#02x}"

    # SW RST
    opcode = await get_mem_output_spi(dut,8)
    assert opcode == 0x66, f"Opcode expected 0x06 got {opcode:#02x}"

    opcode = await get_mem_output_spi(dut,8)
    assert opcode == 0x99, f"Opcode expected 0x99 got {opcode:#02x}"
    dut._log.info("SW RST Done")

    # WIP poll
    opcode = await get_mem_output_return_spi(dut,0xff)
    assert opcode == 0x05, f"Opcode expected 0x05 got {opcode:#02x}"

    opcode = await get_mem_output_return_spi(dut,0xf0)
    assert opcode == 0x05, f"Opcode expected 0x05 got {opcode:#02x}"

    # WREN
    opcode = await get_mem_output_spi(dut,8)
    assert opcode == 0x06, f"Opcode expected 0x06 got {opcode:#02x}"
   
    # global unlock
    opcode = await get_mem_output_spi(dut,8)
    assert opcode == 0x98, f"Opcode expected 0x98 got {opcode:#02x}"
    
    # chip erase
    opcode = await get_mem_output_spi(dut,8)
    assert opcode == 0x06, f"Opcode expected 0x06 got {opcode:#02x}"

    opcode = await get_mem_output_spi(dut,8)
    assert opcode == 0xC7 or opcode == 0x60, f"Opcode expected 0xC7/0x60 got {opcode:#02x}"

    # WIP poll
    opcode = await get_mem_output_return_spi(dut,0xff)
    assert opcode == 0x05, f"Opcode expected 0x05 got {opcode:#02x}"

    opcode = await get_mem_output_return_spi(dut,0xf0)
    assert opcode == 0x05, f"Opcode expected 0x05 got {opcode:#02x}"

    # RDSR2
    #  read stuatus reg 2
    raw_sr2  = random.randint(0,255)
    raw_sr2  &= ~(1 << 1)   # clear bit[1]
    qe_sr2 = (raw_sr2 & ~(1 << 1)) | (1 << 1) # exp sr 2 to be shift out second bit be 1
    opcode = await get_mem_output_return_spi(dut,raw_sr2)
    assert opcode == 0x35, f"Opcode expected 0x35 got {opcode:#02x}"
    # WREN
    opcode = await get_mem_output_spi(dut,8)
    assert opcode == 0x06, f"Opcode expected 0x06 got {opcode:#02x}"
    opcode_qe_sr2 = (0x31 << 8) | qe_sr2
    # WRSR2
    opcode = await get_mem_output_spi(dut,16)
    assert opcode == opcode_qe_sr2, f"Opcode expected {opcode_qe_sr2:#04x} got {opcode:#02x}"

    # WIP poll
    opcode = await get_mem_output_return_spi(dut,0xff)
    assert opcode == 0x05, f"Opcode expected 0x05 got {opcode:#02x}"

    opcode = await get_mem_output_return_spi(dut,0xf0)
    assert opcode == 0x05, f"Opcode expected 0x05 got {opcode:#02x}"

    await ClockCycles(dut.clk,20)
    dut._log.info("Initialization flow done")

# @cocotb.test()
async def sha_encryption_test(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut._log.info("SHA Encryption Start")
    text_addr = 0xff0000
    dest_addr = 0xfe0000
    text = get_random_bytes(32) # get 32 bytes
    hashed = SHA256.new(text).digest()  # hashed result
    #conver to int
    text_int = int.from_bytes(text, "big")
    hashed_int = int.from_bytes(hashed, "big")

    cpu_opcode = make_opcode(1,0x000000,text_addr,dest_addr,0,1)
    # flash coroutine
    flash_task = cocotb.start_soon(sha_flash_model(dut,text_int))

    await send_cpu_opcode(dut,cpu_opcode) # send opcode
    
    await ClockCycles(dut.clk,5)
    valid = 0
    while valid != 1:
        valid, dest = await read_ack_op(dut)
        await RisingEdge(dut.clk)
    rd_opc, rd_addr , wr_opc, wr_addr, output_txt = await flash_task

    assert rd_opc == 0x6B, f"Opcode expected 0x6B got {rd_opc:#02x}"
    assert wr_opc == 0x32, f"Opcode expected 0x32 got {wr_opc:#02x}"
    
    assert rd_addr == text_addr, f"text_addr expected {text_addr:#x} got {rd_addr:#x}"
    assert wr_addr == dest_addr, f"dest_addr expected {dest_addr:#x} got {wr_addr:#x}"
        
    assert output_txt == hashed_int, f"output_txt expected {hashed_int:#x} got {output_txt:#x}"
    dut._log.info("SHA Encryption Passed")

# @cocotb.test()
async def aes_encryption_test(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut._log.info("AES Encryption Start")
    key_addr = 0xfd0000
    text_addr = 0xff0000
    dest_addr = 0xfe0000
    text = get_random_bytes(16) # get 16 bytes
    key = get_random_bytes(32) # get 32 bytes

    # AES-256 ECB encrypt one 16-byte block
    cipher = AES.new(key, AES.MODE_ECB)
    encrypted = cipher.encrypt(text)

    #conver to int
    text_int = int.from_bytes(text, "big")
    key_int = int.from_bytes(key,"big")
    encrypted_int = int.from_bytes(encrypted, "big")
    # aes encrypt
    cpu_opcode = make_opcode(1,key_addr,text_addr,dest_addr,0,0)
    # flash coroutine
    flash_task = cocotb.start_soon(aes_flash_model(dut,key_int,text_int))

    await send_cpu_opcode(dut,cpu_opcode) # send opcode
    
    await ClockCycles(dut.clk,5)
    valid = 0
    while valid != 1:
        valid, dest = await read_ack_op(dut)
        await RisingEdge(dut.clk)
    rd_key_opc, rd_key_addr , rd_txt_opc,rd_txt_addr, wr_opc, wr_addr, output_txt = await flash_task

    assert rd_key_opc == 0x6B, f"Opcode expected 0x6B got {rd_key_opc:#02x}"
    assert rd_txt_opc == 0x6B, f"Opcode expected 0x6B got {rd_txt_opc:#02x}"
    assert wr_opc == 0x32, f"Opcode expected 0x32 got {wr_opc:#02x}"
    
    assert rd_key_addr == key_addr, f"key_addr expected {key_addr:#x} got {rd_key_addr:#x}"
    assert rd_txt_addr == text_addr, f"text_addr expected {text_addr:#x} got {rd_txt_addr:#x}"
    assert wr_addr == dest_addr, f"dest_addr expected {dest_addr:#x} got {wr_addr:#x}"
        
    assert output_txt == encrypted_int, f"output_txt expected {encrypted_int:#x} got {output_txt:#x}"
    dut._log.info("AES Encryption Passed")


# @cocotb.test()
async def aes_decryption_test(dut):
    cocotb.start_soon(Clock(dut.clk, 20, unit="ns").start())
    dut._log.info("AES Decryption Start")
    key_addr = 0xfd0000
    text_addr = 0xff0000
    dest_addr = 0xfe0000
    text = get_random_bytes(16) # get 16 bytes
    key = get_random_bytes(32) # get 32 bytes

    # AES-256 ECB encrypt one 16-byte block
    cipher = AES.new(key, AES.MODE_ECB)
    encrypted = cipher.encrypt(text)

    #conver to int
    text_int = int.from_bytes(text, "big")
    key_int = int.from_bytes(key,"big")
    encrypted_int = int.from_bytes(encrypted, "big")
    # aes decrypt
    cpu_opcode = make_opcode(1,key_addr,text_addr,dest_addr,1,0)
    # flash coroutine
    flash_task = cocotb.start_soon(aes_flash_model(dut,key_int,encrypted_int))

    await send_cpu_opcode(dut,cpu_opcode) # send opcode
    
    await ClockCycles(dut.clk,5)
    valid = 0
    while valid != 1:
        valid, dest = await read_ack_op(dut)
        await RisingEdge(dut.clk)
    rd_key_opc, rd_key_addr , rd_txt_opc,rd_txt_addr, wr_opc, wr_addr, output_txt = await flash_task

    assert rd_key_opc == 0x6B, f"Opcode expected 0x6B got {rd_key_opc:#02x}"
    assert rd_txt_opc == 0x6B, f"Opcode expected 0x6B got {rd_txt_opc:#02x}"
    assert wr_opc == 0x32, f"Opcode expected 0x32 got {wr_opc:#02x}"
    
    assert rd_key_addr == key_addr, f"key_addr expected {key_addr:#x} got {rd_key_addr:#x}"
    assert rd_txt_addr == text_addr, f"text_addr expected {text_addr:#x} got {rd_txt_addr:#x}"
    assert wr_addr == dest_addr, f"dest_addr expected {dest_addr:#x} got {wr_addr:#x}"
        
    assert output_txt == text_int, f"output_txt expected {text_int:#x} got {output_txt:#x}"
    dut._log.info("AES Decryption Passed")
