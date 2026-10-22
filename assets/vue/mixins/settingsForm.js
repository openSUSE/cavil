import UserAgent from '@mojojs/user-agent';

// A settings section backed by /settings/<section>.json, with the section's own data providing settingsUrl
export default {
  data() {
    return {custom: [], defaults: {}, errors: {}, form: null, lastChange: null, response: {}, saved: {}, saving: false};
  },
  computed: {
    dirtyValues() {
      if (this.form === null) return {};
      const dirty = {};
      for (const [key, value] of Object.entries(this.form)) {
        if (JSON.stringify(value) !== JSON.stringify(this.saved[key])) dirty[key] = value;
      }
      return dirty;
    },
    dirty() {
      return Object.keys(this.dirtyValues).length > 0;
    }
  },
  async mounted() {
    const ua = new UserAgent({baseURL: window.location.href});
    this.load(await (await ua.get(this.settingsUrl)).json());
  },
  methods: {
    load(data) {
      this.response = data;
      this.custom = data.custom;
      this.defaults = data.defaults;
      this.lastChange = data.last_change;
      this.saved = data.values;
      this.form = JSON.parse(JSON.stringify(data.values));
    },
    reset(name) {
      return this.send({reset: [name]});
    },
    save() {
      return this.send({values: this.dirtyValues});
    },
    async send(body) {
      this.saving = true;
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.put(this.settingsUrl, {json: body});
      const data = await res.json().catch(() => ({}));
      this.saving = false;

      if (!res.isSuccess) {
        this.errors = data.errors ?? {};
        this.$refs.toaster.notify(data.error ?? 'Settings could not be saved', 'danger', 5000);
        return;
      }

      const pending = this.dirtyValues;
      for (const key of body.reset ?? []) delete pending[key];
      this.errors = {};
      this.load(data);
      Object.assign(this.form, JSON.parse(JSON.stringify(pending)));

      const n = data.rechecked;
      this.$refs.toaster.notify(
        n > 0 ? `Saved. ${n} open ${n === 1 ? 'review' : 'reviews'} will be checked again.` : 'Saved.'
      );
    }
  }
};
