import sys

span = float(open(sys.argv[1]).read())
print("demo span", span)
if not 55 <= span <= 95:
    raise SystemExit(f"demo span {span} is outside 55-95 seconds")
