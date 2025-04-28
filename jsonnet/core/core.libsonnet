local manifest = import './manifest.libsonnet';
local validate = import './validate.libsonnet';

manifest + validate + {
  Object: self.Manifest + self.Validate + {
    __manifest__+:: {
      prune_null: true,
      prune_empty_list: true,
      prune_empty_object: true,
      prune_false: true,
    },
  },
}