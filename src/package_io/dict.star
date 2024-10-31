def sort_dict_by_values(d):
    sorted_items = sorted(d.items(), key=lambda x: x[0])
    return {k: v for k, v in sorted_items}
