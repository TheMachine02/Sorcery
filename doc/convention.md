# Call convention

Generally, the caller should preserve register that may be destroyed by the callee. In some rare and special case, like for queue routine, malloc routine (time sensitive, place sensitive routine and very frequently called routine), the callee save register itself. In those case, it should be documented and caller can call it without the need to preserve register (or only the ouput register)
 
Syscall may destroy all register if called externally with call. If called through syscall, all register except hl (output result) are destroyed.

# Naming convention

Label name should follow the snake_case convention.
In case of define indicating offset within structure, they should be UPPER_CASE
Other memory specific area can use both. Usually, defined table use the UPPER_CASE and structure use the snake_case

# Assembly convention

Use a 8 space alt at the begin of the line containing an opcode, an alt after the opcode, and a space after the ','  of the first operand
Commentary should be put either after the instruction or on the line before.
