"""
VCD Parser for Hardware Root-of-Trust (RoT) Engine
Extracts key signal transitions from rot_top.vcd and exports them to dashboard/vcd_data.js
"""
import os
import json
import re

def parse_vcd(vcd_path):
    signals = {}       # id -> {'name': str, 'type': str, 'size': int}
    var_map = {}       # sname -> id
    timescale = "1ps"
    
    with open(vcd_path, 'r', encoding='utf-8', errors='ignore') as f:
        scope = []
        in_header = True
        
        for line in f:
            line = line.strip()
            if not line:
                continue
            
            if in_header:
                if line.startswith('$timescale'):
                    pass
                elif line.startswith('$scope'):
                    parts = line.split()
                    if len(parts) >= 3:
                        scope.append(parts[2])
                elif line.startswith('$upscope'):
                    if scope:
                        scope.pop()
                elif line.startswith('$var'):
                    parts = line.split()
                    if len(parts) >= 5:
                        var_type = parts[1]
                        var_size = int(parts[2])
                        var_id = parts[3]
                        var_name = parts[4]
                        full_name = '.'.join(scope + [var_name])
                        signals[var_id] = {
                            'name': full_name,
                            'short_name': var_name,
                            'type': var_type,
                            'size': var_size
                        }
                        var_map[full_name] = var_id
                elif line.startswith('$enddefinitions'):
                    in_header = False
                    break

    print(f"Header parsed: {len(signals)} signals found.")
    
    # We want key top-level and DUT signals
    interest_keywords = [
        'pclk', 'presetn', 'paddr', 'psel', 'penable', 'pwrite', 'pwdata', 'prdata',
        'pready', 'pslverr', 'rot_zeroize_pin', 'rot_alarm_out', 'rot_irq',
        'key_ready', 'aes_start', 'round_num', 'state_valid', 'ghash_valid', 'ghash_tag',
        'keccak_round', 'keccak_done', 'mode', 'key_locked'
    ]
    
    selected_ids = {}
    for vid, meta in signals.items():
        sname = meta['short_name'].lower()
        fname = meta['name'].lower()
        for kw in interest_keywords:
            if kw in sname or (kw in fname and ('tb_rot_top' in fname or 'u_dut' in fname)):
                selected_ids[vid] = meta
                break
                
    print(f"Selected {len(selected_ids)} signals of interest.")
    for vid, meta in list(selected_ids.items())[:15]:
        print(f"  [{vid}] {meta['name']} ({meta['size']}-bit)")

    # Second pass: read simulation events
    timeline = [] # list of (time_ps, changes_dict)
    current_time = 0
    current_changes = {}
    
    with open(vcd_path, 'r', encoding='utf-8', errors='ignore') as f:
        # skip header
        for line in f:
            if '$enddefinitions' in line:
                break
                
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('#'):
                t_str = line[1:].strip()
                new_time = int(t_str)
                if current_changes:
                    timeline.append({'time_ps': current_time, 'time_ns': current_time / 1000.0, 'vals': current_changes})
                    current_changes = {}
                current_time = new_time
            elif line.startswith('$dumpvars') or line.startswith('$end'):
                continue
            else:
                # Value change
                # Formats: '0!', '1!', 'b1010 !', 'r1.234 !'
                if line.startswith('b') or line.startswith('B'):
                    parts = line.split()
                    val = parts[0][1:]
                    vid = parts[1] if len(parts) > 1 else ''
                    if vid in selected_ids:
                        current_changes[selected_ids[vid]['name']] = hex(int(val, 2)) if val.replace('0','').replace('1','') == '' else val
                elif line.startswith('r') or line.startswith('R'):
                    pass
                else:
                    val = line[0]
                    vid = line[1:]
                    if vid in selected_ids:
                        current_changes[selected_ids[vid]['name']] = val

        if current_changes:
            timeline.append({'time_ps': current_time, 'time_ns': current_time / 1000.0, 'vals': current_changes})

    print(f"Timeline extracted: {len(timeline)} time slices.")
    return selected_ids, timeline

if __name__ == '__main__':
    vcd_path = 'rot_top.vcd'
    if os.path.exists(vcd_path):
        selected_ids, timeline = parse_vcd(vcd_path)
        out_js = 'dashboard/vcd_data.js'
        os.makedirs('dashboard', exist_ok=True)
        with open(out_js, 'w', encoding='utf-8') as f:
            f.write("// Auto-generated from rot_top.vcd (QuestaSim 10.7c)\n")
            f.write("window.PRELOADED_VCD_SIGNALS = " + json.dumps(list(selected_ids.values()), indent=2) + ";\n")
            f.write("window.PRELOADED_VCD_TIMELINE = " + json.dumps(timeline, indent=2) + ";\n")
        print(f"Saved {out_js} successfully.")
    else:
        print("rot_top.vcd not found!")
