#!/usr/bin/env python3
import struct
import os
import glob

def check_indices(keys_dir="sw/tools/keys"):
    print(f"==================================================")
    print(f"   XMSS Key Index Checker")
    print(f"==================================================")
    
    if not os.path.exists(keys_dir):
        print(f"Error: Directory {keys_dir} not found.")
        return

    sk_files = glob.glob(os.path.join(keys_dir, "*.sk"))
    
    if not sk_files:
        print(f"No secret keys (.sk) found in {keys_dir}.")
        return

    for sk_file in sorted(sk_files):
        key_name = os.path.basename(sk_file)
        try:
            with open(sk_file, "rb") as f:
                f.seek(4) # Skip the 4-byte OID
                index_bytes = f.read(4)
                if len(index_bytes) == 4:
                    idx = struct.unpack(">I", index_bytes)[0]
                    print(f"[+] Key: {key_name:<15} | Next Index: {idx}")
                else:
                    print(f"[-] Key: {key_name:<15} | Error: File too small")
        except Exception as e:
            print(f"[-] Key: {key_name:<15} | Error: {e}")
            
    print(f"==================================================")

if __name__ == "__main__":
    check_indices()
