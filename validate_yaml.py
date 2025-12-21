import yaml

try:
    with open('.github/workflows/build-openwrt-r68s.yml', 'r') as f:
        yaml.safe_load(f)
    print('YAML syntax is valid.')
except yaml.YAMLError as e:
    print('YAML syntax error:')
    print(e)
except Exception as e:
    print('Error:', e)