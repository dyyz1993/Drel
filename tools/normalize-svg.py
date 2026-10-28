import re, sys

def norm(path):
    s = open(path, encoding="utf-8").read()
    s = re.sub(r'\s(viewBox|max-width|width|height)="[^"]*"', '', s)
    s = re.sub(r'\s(x|y|x1|y1|x2|y2|cx|cy|r|rx|ry|width|height|d|points)="[^"]*"', '', s)
    s = re.sub(r'\sstyle="[^"]*"', '', s)
    s = re.sub(r'\sfont-size="[^"]*"', '', s)
    s = re.sub(r'\sdy="[^"]*"', '', s)
    s = re.sub(r'\sdominant-baseline="[^"]*"', '', s)
    s = re.sub(r'\salignment-baseline="[^"]*"', '', s)
    s = re.sub(r'\stransform="[^"]*"', '', s)
    s = re.sub(r'>\s+<', '><', s)
    return s.strip()

print(norm(sys.argv[1]))
