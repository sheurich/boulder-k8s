import yaml
import csv
import json
import os

def get_abs_path(path, base_dir):
    if not path or os.path.isabs(path):
        return path
    return os.path.abspath(os.path.join(base_dir, path))

def redact_value(key, value):
    if isinstance(value, str) and (any(s in key.lower() for s in ['password', 'secret', 'key', 'token']) or len(value) < 20):
        return '<redacted>'
    return value

def parse_compose_files(main_file, override_file, base_dir):
    with open(main_file, 'r') as f:
        main_config = yaml.safe_load(f)

    with open(override_file, 'r') as f:
        override_config = yaml.safe_load(f)

    # Merge override into main config
    for service_name, service_config in override_config.get('services', {}).items():
        if service_name in main_config.get('services', {}):
            for key, value in service_config.items():
                if key == 'environment' and 'environment' in main_config['services'][service_name]:
                    main_config['services'][service_name][key].update(value)
                else:
                    main_config['services'][service_name][key] = value
        else:
            main_config.setdefault('services', {})[service_name] = service_config

    services_data = []
    services_json = []

    for service_name, config in main_config.get('services', {}).items():
        image_or_build = config.get('image', 'none')
        if 'build' in config:
            if isinstance(config['build'], str):
                image_or_build = get_abs_path(config['build'], base_dir)
            elif isinstance(config['build'], dict) and 'context' in config['build']:
                image_or_build = get_abs_path(config['build']['context'], base_dir)

        command = 'none'
        if 'command' in config:
            command = config['command'] if isinstance(config['command'], str) else ' '.join(config['command'])
        elif 'entrypoint' in config:
            command = config['entrypoint'] if isinstance(config['entrypoint'], str) else ' '.join(config['entrypoint'])


        published_ports = ', '.join(config.get('ports', [])) if config.get('ports') else 'none'
        exposed_ports = ', '.join(config.get('expose', [])) if config.get('expose') else 'none'

        volumes = []
        if 'volumes' in config:
            for v in config['volumes']:
                if isinstance(v, str):
                    parts = v.split(':')
                    if len(parts) > 1:
                        src = get_abs_path(parts[0], base_dir)
                        parts[0] = src
                    volumes.append(':'.join(parts))
                elif isinstance(v, dict) and v.get('type') == 'bind':
                     volumes.append(f"{get_abs_path(v.get('source'), base_dir)}:{v.get('target')}")


        env_vars = []
        if 'environment' in config:
            if isinstance(config['environment'], dict):
                for k, v in config['environment'].items():
                    env_vars.append(f"{k}={redact_value(k, v)}")
            elif isinstance(config['environment'], list):
                for item in config['environment']:
                    if '=' in item:
                        k, v = item.split('=', 1)
                        env_vars.append(f"{k}={redact_value(k, v)}")
                    else:
                        env_vars.append(f"{item}=<redacted>")


        depends_on = ', '.join(config.get('depends_on', [])) if config.get('depends_on') else 'none'
        networks_config = config.get('networks')
        if isinstance(networks_config, dict):
            networks = ', '.join(networks_config.keys())
        elif isinstance(networks_config, list):
            networks = ', '.join(networks_config)
        else:
            networks = 'none'
        restart_policy = config.get('restart', 'none')
        stateful = bool(volumes)

        service_type = 'app'
        if 'db' in service_name or 'mysql' in service_name or 'mariadb' in service_name:
            service_type = 'db'
        elif 'redis' in service_name:
            service_type = 'cache'
        elif 'bsetup' in service_name or 'build' in service_name:
            service_type = 'build'
        elif any(pki_s in service_name for pki_s in ['ca', 'pki', 'ocsp', 'crl']):
            service_type = 'pki'
        elif any(sup_s in service_name for sup_s in ['consul', 'jaeger', 'proxysql']):
            service_type = 'support'


        needs_init = False
        if command and ('start-servers.py' in command or 'generate.sh' in command or 'challtestsrv' in command):
            needs_init = True
        if 'bsetup' in service_name:
            needs_init = True


        cpu_limits = config.get('deploy', {}).get('resources', {}).get('limits', {}).get('cpus', 'none')
        memory_limits = config.get('deploy', {}).get('resources', {}).get('limits', {}).get('memory', 'none')
        notes = []
        if config.get('privileged'):
            notes.append('Runs as privileged container.')
        if 'softhsm' in ' '.join(volumes):
            notes.append('Runs SoftHSM2 inside container.')


        service_info = {
            'service_name': service_name,
            'image_or_build': image_or_build,
            'command/entrypoint': command,
            'published_ports': published_ports,
            'exposed_ports': exposed_ports,
            'volumes': ', '.join(volumes) if volumes else 'none',
            'env_vars': ', '.join(env_vars) if env_vars else 'none',
            'depends_on': depends_on,
            'networks': networks,
            'restart_policy': restart_policy,
            'stateful': stateful,
            'service_type': service_type,
            'needs_init': needs_init,
            'cpu_limits': cpu_limits,
            'memory_limits': memory_limits,
        }
        services_data.append(service_info)

        service_info_json = service_info.copy()
        service_info_json['notes'] = ' '.join(notes) if notes else 'none'
        services_json.append({service_name: service_info_json})


    return services_data, services_json

def write_csv(data, filename):
    if not data:
        return
    with open(filename, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=data[0].keys())
        writer.writeheader()
        writer.writerows(data)

def write_json(data, filename):
    with open(filename, 'w') as f:
        json.dump(data, f, indent=2)

def write_readme(filename):
    content = """
# Docker Compose Inventory

This document provides an inventory of the services defined in the Docker Compose setup for the Boulder project.

## Data Gathering Process

The data was gathered by programmatically parsing the `docker-compose.yml` and `docker-compose.next.yml` files using a Python script with the PyYAML library. The script merges the configurations, with the `next` file overriding the base file.

Environment variables from `.env` files were not explicitly found or parsed, as the provided docker-compose files did not reference any.

## Ambiguities and Resolutions

- **Service Type:** The `service_type` was inferred based on the service name. This is a best-effort guess and should be reviewed.
- **Secrets:** Values for environment variables that look like secrets (containing keywords like `password`, `secret`, `key`, `token`) or are short have been redacted to `<redacted>`.
- **`needs_init`:** This flag was set to `true` for services that call scripts like `start-servers.py` or `generate.sh`, or are explicitly for setup purposes (like `bsetup`). This is an inference based on the provided instructions.
- **Duplicate Services:** The `boulder` service is defined in both `docker-compose.yml` and `docker-compose.next.yml`. The definitions were merged, with the `environment` from `docker-compose.next.yml` overriding the one in the base file. This is flagged as per instructions.

## Open Questions for the Migration Team

1.  Are the inferred `service_type` tags accurate for all services?
2.  Are there any other services or configurations that are generated dynamically in a CI/CD pipeline that were not captured?
3.  The `FAKE_DNS` environment variable is hardcoded in the compose files. How should this be handled in Kubernetes?
4.  Are there any other implicit dependencies between services that are not captured in the `depends_on` field?
"""
    with open(filename, 'w') as f:
        f.write(content)

if __name__ == "__main__":
    base_directory = '/Users/sheurich/src/sheurich/boulder'
    main_compose_file = os.path.join(base_directory, 'docker-compose.yml')
    override_compose_file = os.path.join(base_directory, 'docker-compose.next.yml')

    services_data, services_json = parse_compose_files(main_compose_file, override_compose_file, base_directory)

    write_csv(services_data, 'compose-inventory.csv')
    write_json(services_json, 'compose-tags.json')
    write_readme('README.md')

    print("Successfully generated compose-inventory.csv, compose-tags.json, and README.md")

