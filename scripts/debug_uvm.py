with open('rot_uvm_waves.vcd', 'r', errors='ignore') as f:
    vars_map = {}
    scope = []
    for line in f:
        line = line.strip()
        if line.startswith('$scope'):
            scope.append(line.split()[2])
        elif line.startswith('$upscope'):
            if scope: scope.pop()
        elif line.startswith('$var'):
            p = line.split()
            if len(p) >= 5:
                full_name = '.'.join(scope + [p[4]])
                vars_map[p[3]] = (full_name, p[4], p[2])
        elif line.startswith('$enddefinitions'):
            break

# Find APB signals and AES core inputs
targets = {}
for sid, (fname, sname, sz) in vars_map.items():
    if ('u_dut' in fname and sname in ['paddr', 'pwdata', 'prdata', 'psel', 'penable', 'aes_data_valid', 'aes_out_valid', 'aes_out_data', 'key_commit', 'key_load_req']) or ('u_aes_core_inst' in fname and sname in ['data_in', 'cipher_key', 'data_out']):
        targets[sid] = (sname, sz, fname)

print(f"Total targets: {len(targets)}")
for sid, (sname, sz, fname) in targets.items():
    print(f"  {sid} -> {sname} ({sz}b) [{fname}]")

with open('rot_uvm_waves.vcd', 'r', errors='ignore') as f:
    current_time = 0
    for line in f:
        line = line.strip()
        if not line: continue
        if line.startswith('#'):
            current_time = int(line[1:])
            if current_time > 600000:
                break
        elif line.startswith('b'):
            parts = line[1:].split()
            if len(parts) == 2:
                val, sid = parts
                if sid in targets:
                    sname, sz, fname = targets[sid]
                    try:
                        hval = hex(int(val, 2))
                    except:
                        hval = val
                    print(f"[{current_time} ps] {sname} = {hval}")
        elif len(line) > 1 and line[-1] in targets:
            sid = line[-1]
            val = line[:-1]
            sname, sz, fname = targets[sid]
            print(f"[{current_time} ps] {sname} = {val}")
