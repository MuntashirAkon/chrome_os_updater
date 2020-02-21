#!/usr/bin/env python
# 2019 (c) Muntashir Al-Islam. All rights reserved.
# status_result_to_pb_array.py

from update_engine_pb2 import StatusResult
from sys import argv

stringToBool={'0': False, '1': True, 'true': True, 'false': False}

status_result = argv[1:]

res = StatusResult()
res.last_checked_time = int(status_result[0])
res.progress = float(status_result[1])
res.current_operation = int(status_result[2])
res.new_version = status_result[3]
res.new_size = int(status_result[4])
res.is_enterprise_rollback = stringToBool[status_result[5]]
res.is_install = stringToBool[status_result[6]]
res.eol_date = int(status_result[7])

string_arr = []

for i in res.SerializeToString():
    string_arr.append(str(i))

print(",".join(string_arr))