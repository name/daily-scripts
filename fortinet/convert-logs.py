import codecs
import csv
import re
import sys

if len(sys.argv) > 1:
    filename = str(sys.argv[1])
else:
    raise Exception("No input file specified")

print("[+] Reading logs from " + filename)
try:
    log_data = codecs.open(filename, "r", encoding="UTF-8")
except:
    raise Exception("Invalid input file")
pattern = re.compile(
    '(\w+)(?:=)(?:"{1,3}([\w\-\.:\ =]+)"{1,3})|(\w+)=(?:([\w\-\.:\=]+))'
)
events = []

for line in log_data:
    event = {}
    match = pattern.findall(line)
    for group in match:
        if group[0] != "":
            event[group[0]] = group[1]
        else:
            event[group[2]] = group[3]
    events.append(event)

print("[+] Processing log fields")
headers = []
for row in events:
    for key in row.keys():
        if not key in headers:
            headers.append(key)

print("[+] Writing CSV")
newfilename = (filename.split("/")[len(filename.split("/")) - 1].split(".")[0]) + ".csv"
with open(newfilename, "w", newline="", encoding="utf-8") as fileh:
    csvfile = csv.DictWriter(fileh, headers)
    csvfile.writeheader()
    for row in events:
        csvfile.writerow(row)
print("[+] Finished - " + str(len(events)) + " rows written to " + newfilename)
