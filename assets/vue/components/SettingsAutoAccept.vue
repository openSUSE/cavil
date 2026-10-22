<template>
  <section>
    <div class="cavil-settings-header">
      <h3>Automatic acceptance</h3>
      <p>Decide which new reviews Cavil may accept without a person looking at them.</p>
      <p>Open reviews are checked again when you save, decisions already made stay as they are.</p>
    </div>

    <LegalLoading v-if="form === null" message="Loading settings..." size="small" />
    <form v-else @submit.prevent="save()">
      <div class="cavil-settings-rule cavil-settings-rule-checkbox">
        <div class="form-check">
          <input id="low-risk-enabled" v-model="lowRiskEnabled" class="form-check-input" type="checkbox" />
          <label for="low-risk-enabled" class="form-check-label"
            >Accept low-risk packages nobody has reviewed yet</label
          >
          <SettingsDefaultLabel :name="'auto_accept_risk'" :custom="custom" @reset="reset" />
        </div>
        <p class="cavil-settings-help">
          A package needs one review by a person before later versions can be accepted on their history. This rule makes
          an exception for packages whose licenses are all low risk.
        </p>
        <Transition name="cavil-reveal">
          <div v-if="lowRiskEnabled" class="cavil-reveal">
            <div class="cavil-settings-nested">
              <label for="auto-accept-risk" class="form-label">Only when every license found is at most</label>
              <select id="auto-accept-risk" v-model.number="form.auto_accept_risk" class="form-select">
                <option v-for="level in levels(1, form.acceptable_risk)" :key="level" :value="level">
                  {{ level }} - {{ riskName(level) }}
                </option>
              </select>
              <div v-if="errors.auto_accept_risk" class="cavil-settings-error">{{ errors.auto_accept_risk }}</div>
            </div>
          </div>
        </Transition>
      </div>

      <div class="cavil-settings-rule">
        <label for="acceptable-risk" class="cavil-settings-label">Accept packages a person has reviewed before</label>
        <SettingsDefaultLabel :name="'acceptable_risk'" :custom="custom" @reset="reset" />
        <p class="cavil-settings-help">
          When an earlier version was reviewed, a new version is accepted as long as no license is riskier than this.
          Command-line and CI reviews also use it as their pass or fail line.
        </p>
        <div class="cavil-settings-nested">
          <select id="acceptable-risk" v-model.number="form.acceptable_risk" class="form-select">
            <option v-for="level in levels(1, 7, form.acceptable_risk)" :key="level" :value="level">
              {{ level }} - {{ riskName(level) }}
            </option>
          </select>
          <div v-if="errors.acceptable_risk" class="cavil-settings-error">{{ errors.acceptable_risk }}</div>
        </div>
      </div>

      <div class="cavil-settings-rule">
        <label for="acceptable-packages" class="cavil-settings-label">Always accept these packages</label>
        <SettingsDefaultLabel :name="'acceptable_packages'" :custom="custom" @reset="reset" />
        <p class="cavil-settings-help">
          Packages accepted by name alone, such as placeholder packages without real source code. Press Enter after each
          name.
        </p>
        <div class="cavil-settings-nested" id="acceptable-packages">
          <TagInput
            v-model="form.acceptable_packages"
            :max-length="255"
            :max-tags="1000"
            placeholder="Add a package name"
            data-key="acceptable-packages"
          />
          <div v-if="errors.acceptable_packages" class="cavil-settings-error">{{ errors.acceptable_packages }}</div>
        </div>
      </div>

      <div class="cavil-settings-footer">
        <button type="submit" class="btn btn-success" id="settings-save" :disabled="!dirty || saving">
          Save changes
        </button>
        <SettingsLastChange :change="lastChange" empty="Using default values" />
      </div>
    </form>
    <ToastNotifier ref="toaster" />
  </section>
</template>

<script>
import LegalLoading from './LegalLoading.vue';
import SettingsDefaultLabel from './SettingsDefaultLabel.vue';
import SettingsLastChange from './SettingsLastChange.vue';
import TagInput from './TagInput.vue';
import ToastNotifier from './ToastNotifier.vue';
import {riskName} from '../helpers/riskLevels.js';
import UserAgent from '@mojojs/user-agent';

const SETTINGS_URL = '/settings/auto-accept.json';

export default {
  name: 'SettingsAutoAccept',
  components: {LegalLoading, SettingsDefaultLabel, SettingsLastChange, TagInput, ToastNotifier},
  data() {
    return {custom: [], defaults: {}, errors: {}, form: null, lastChange: null, saved: {}, saving: false};
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
    },
    lowRiskEnabled: {
      get() {
        return this.form.auto_accept_risk > 0;
      },
      set(enabled) {
        this.form.auto_accept_risk = enabled ? Math.min(this.defaults.auto_accept_risk, this.form.acceptable_risk) : 0;
      }
    }
  },
  watch: {
    'form.acceptable_risk'(risk) {
      if (this.form.auto_accept_risk > risk) this.form.auto_accept_risk = risk;
    }
  },
  async mounted() {
    const ua = new UserAgent({baseURL: window.location.href});
    this.load(await (await ua.get(SETTINGS_URL)).json());
  },
  methods: {
    levels(from, to, current) {
      const levels = [];
      for (let level = from; level <= to; level++) levels.push(level);
      if (current !== undefined && !levels.includes(current)) levels.push(current);
      return levels;
    },
    load(data) {
      this.custom = data.custom;
      this.defaults = data.defaults;
      this.lastChange = data.last_change;
      this.saved = data.values;
      this.form = JSON.parse(JSON.stringify(data.values));
    },
    reset(name) {
      return this.send({reset: [name]});
    },
    riskName,
    save() {
      return this.send({values: this.dirtyValues});
    },
    async send(body) {
      this.saving = true;
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.put(SETTINGS_URL, {json: body});
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
</script>
