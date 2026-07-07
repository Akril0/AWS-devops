def swarm_nodes_matching_field_value(hostvars, variable, field='stdout', nodes=None, value='true'):
    ret = []

    for node in hostvars.keys():
        if (
                (
                    nodes is None or
                    (
                        isinstance(nodes, list) and
                        node in nodes or
                        node == nodes
                    )
                ) and
                variable in hostvars[node] and
                field in hostvars[node][variable] and
                hostvars[node][variable][field] == value):
            ret.append(node)

    return ret

def swarm_nodes_remove(hostvars, node, data):
    ret = []

    for k, v in data.items():
        if (
                'state' in v and
                v['state'] == 'absent'):
            ret.append(k)

    return ret

def swarm_nodes_membership(hostvars, value='active', nodes=None):
    variable = 'docker_swarm__check_membership_result'
    field = 'stdout'

    return swarm_nodes_matching_field_value(hostvars, variable, field, nodes, value)

def swarm_nodes_managership(hostvars, value='true', nodes=None):
    variable = 'docker_swarm__check_manager_result'
    field = 'stdout'

    return swarm_nodes_matching_field_value(hostvars, variable, field, nodes, value)

def swarm_node_set_labels(hostvars, node, data, default):
    ret = []

    if (
            node not in hostvars or
            'docker_swarm_labels_result' not in hostvars[node] or
            'results' not in hostvars[node]['docker_swarm_labels_result']):
        return ret

    current = {}

    for result in hostvars[node]['docker_swarm_labels_result']['results']:
        if 'item' in result and 'stdout_lines' in result:
            c_node = result['item']
            current[c_node] = {}

            for pair in result['stdout_lines']:
                k, v = pair.split('=', 1)

                current[c_node][k] = v

    required = {}

    for r_node in current.keys():
        required[r_node] = dict(default)

        if r_node in data and 'labels' in data[r_node]:
            required[r_node].update(data[r_node]['labels'])

    for n in current.keys():
        for k in set(current[n]) - set(required[n]):
            ret.append({'node': n, 'command': "--label-rm %s" % k})

        for k, v in required[n].items():
            if k not in current[n] or str(v) != current[n][k]:
                ret.append({'node': n, 'command': "--label-add %s=%s" % (k, v)})

    return ret

class FilterModule(object):
    def filters(self):

        return {
            'swarm_nodes_membership': swarm_nodes_membership,
            'swarm_nodes_managership': swarm_nodes_managership,
            'swarm_nodes_remove': swarm_nodes_remove,
            'swarm_nodes_matching_field_value': swarm_nodes_matching_field_value,
            'swarm_node_set_labels': swarm_node_set_labels,
        }
