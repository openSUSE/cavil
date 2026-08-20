<template>
  <div class="pattern-editor" :class="{'pattern-editor-inline': inline}">
    <div v-if="error" class="alert alert-danger" role="alert">{{ error }}</div>

    <div v-if="!isNew && showMatchCount" class="row">
      <div class="col mb-3 edit-pattern-match-count">
        <span v-if="matchCount === null && matchCountError === null">
          <LegalLoading message="Loading match count" size="small" />
        </span>
        <span v-else-if="matchCountError !== null" class="text-danger">{{ matchCountError }}</span>
        <span v-else-if="matchCount.matches === 0">This pattern has no matches.</span>
        <span v-else>
          This pattern has <b>{{ matchCount.matches }}</b> {{ matchCount.matches === 1 ? 'match' : 'matches' }} in
          <b>{{ matchCount.packages }}</b
          >{{ ' '
          }}<a :href="`/search?pattern=${pattern.id}`">{{ matchCount.packages === 1 ? 'package' : 'packages' }}</a
          >.
        </span>
      </div>
    </div>

    <div class="pattern-editor-tabs" role="tablist">
      <button
        type="button"
        class="pattern-editor-tab"
        :class="{active: activeTab === 'edit'}"
        role="tab"
        :aria-selected="activeTab === 'edit'"
        data-tab="edit"
        @click="setActiveTab('edit')"
      >
        <i class="fa-solid fa-pen-to-square"></i> Edit
      </button>
      <button
        type="button"
        class="pattern-editor-tab"
        :class="{active: activeTab === 'closest'}"
        role="tab"
        :aria-selected="activeTab === 'closest'"
        data-tab="closest"
        :disabled="closest === null"
        @click="setActiveTab('closest')"
      >
        <i class="fa-solid fa-magnifying-glass"></i>
        Closest match
        <span v-if="closest !== null" class="pattern-editor-tab-badge">{{ closest.similarity }}%</span>
      </button>
    </div>

    <div class="pattern-editor-tab-content">
      <div
        class="pattern-editor-tab-pane"
        :class="{'is-active': activeTab === 'edit'}"
        :aria-hidden="activeTab !== 'edit'"
      >
        <div class="row">
          <form :action="formAction" method="POST" @submit="onSubmit">
            <div class="col mb-3">
              <label class="form-label" for="license">License</label>
              <div class="pattern-editor-autocomplete-anchor">
                <input
                  v-model="form.license"
                  @input="autocomplete"
                  @focus="licenseFocused = true"
                  @blur="licenseFocused = false"
                  ref="license"
                  type="text"
                  name="license"
                  id="license"
                  class="form-control"
                  autocomplete="off"
                />
                <div v-show="licenseFocused && results.length > 0" class="autocomplete-container">
                  <div class="autocomplete">
                    <div
                      v-for="(result, i) in results"
                      :key="i"
                      @mousedown.prevent="fillLicense(result)"
                      class="autocomplete-item"
                    >
                      {{ result }}
                    </div>
                  </div>
                </div>
              </div>
              <div class="form-text">Auto-completed license names will also predict the risk value.</div>
            </div>
            <div v-if="!isNew && showSpdx" class="col mb-3">
              <label class="form-label" for="spdx">SPDX</label>
              <input :value="pattern.spdx" type="text" id="spdx" class="form-control" disabled />
            </div>
            <div class="col mb-3">
              <label class="form-label" for="pattern-text">Pattern</label>
              <PatternCodeMirror v-model="form.pattern" />
              <textarea name="pattern" :value="form.pattern" class="edit-pattern-hidden"></textarea>
            </div>

            <div class="col mb-3">
              <div class="row">
                <div class="col-lg-2 mb-3">
                  <div class="form-floating">
                    <select v-model="form.risk" name="risk" id="risk" class="form-control">
                      <option v-for="r in 10" :key="r - 1" :value="String(r - 1)">{{ r - 1 }}</option>
                    </select>
                    <label for="risk" class="form-label">Risk</label>
                  </div>
                </div>
                <div class="col-lg-6 pattern-editor-flags">
                  <PatternFlags v-model="form" />
                </div>
              </div>
            </div>

            <div class="col mb-3">
              <label class="form-label" for="packname">Package</label>
              <input v-model="form.packname" type="text" name="packname" id="packname" class="form-control" />
              <div id="packageHelp" class="form-text">Leave this field empty to apply pattern to all packages</div>
            </div>

            <div class="col mb-4 pattern-editor-actions">
              <button type="submit" class="btn btn-primary" :disabled="saving">
                <i v-if="saving" class="fa-solid fa-rotate fa-spin"></i>
                {{ isNew ? 'Create' : inline ? 'Save changes' : 'Update' }}
              </button>
              <button v-if="inline" type="button" class="btn btn-secondary" :disabled="saving" @click="$emit('cancel')">
                Cancel
              </button>
              <button
                v-if="!isNew"
                type="button"
                class="del-pattern btn btn-danger btn-sm"
                :disabled="saving"
                @click="onDelete"
              >
                Delete
              </button>
            </div>
          </form>
        </div>
      </div>
      <div
        class="pattern-editor-tab-pane"
        :class="{'is-active': activeTab === 'closest'}"
        :aria-hidden="activeTab !== 'closest'"
      >
        <ClosestPattern :pattern="form.pattern" :exclude-id="pattern.id ?? null" @loaded="onClosestLoaded" />
      </div>
    </div>
  </div>
</template>

<script>
import ClosestPattern from './ClosestPattern.vue';
import LegalLoading from './LegalLoading.vue';
import PatternCodeMirror from './PatternCodeMirror.vue';
import PatternFlags, {LICENSE_FLAGS, PATTERN_FLAGS} from './PatternFlags.vue';
import {rankLicenses} from '../helpers/licenseAutocomplete.js';
import UserAgent from '@mojojs/user-agent';

export default {
  name: 'PatternEditor',
  components: {ClosestPattern, LegalLoading, PatternCodeMirror, PatternFlags},
  props: {
    pattern: {type: Object, required: true},
    inline: {type: Boolean, default: false},
    showMatchCount: {type: Boolean, default: true},
    showSpdx: {type: Boolean, default: true}
  },
  emits: ['saved', 'deleted', 'cancel'],
  data() {
    return {
      form: this.formFromPattern(this.pattern),
      activeTab: 'edit',
      closest: null,
      matchCount: null,
      matchCountError: null,
      saving: false,
      error: null,
      licenses: {},
      suggestions: [],
      results: [],
      licenseFocused: false,
      ua: new UserAgent({baseURL: window.location.href})
    };
  },
  computed: {
    isNew() {
      return this.pattern.id == null;
    },
    formAction() {
      return this.isNew ? '/licenses/create_pattern' : `/licenses/update_pattern/${this.pattern.id}`;
    }
  },
  mounted() {
    if (!this.isNew && this.showMatchCount) this.loadMatchCount();
    this.loadLicenses();
  },
  methods: {
    async loadLicenses() {
      try {
        const res = await this.ua.get('/licenses/autocomplete.json');
        if (!res.isSuccess) return;
        this.licenses = await res.json();
        this.suggestions = Object.keys(this.licenses);
        this.results = this.suggestions;
      } catch (_error) {
        // Autocomplete is a convenience; a failed fetch just leaves the field as a plain text input
      }
    },
    autocomplete() {
      this.results = rankLicenses(this.suggestions, this.form.license);
    },
    fillLicense(result) {
      if (this.$refs.license) this.$refs.license.blur();
      this.form.license = result;
      const options = this.licenses[result];
      if (options !== undefined) {
        this.form.risk = String(options.risk);

        // Only the license's own properties; full_license_text is about this pattern's text
        for (const flag of LICENSE_FLAGS) this.form[flag.name] = !!options[flag.name];
      }
      this.results = this.suggestions;
      this.licenseFocused = false;
    },
    formFromPattern(pattern) {
      return {
        license: pattern.license ?? '',
        pattern: pattern.pattern ?? '',
        risk: String(pattern.risk ?? 0),
        packname: pattern.packname ?? '',
        ...Object.fromEntries(PATTERN_FLAGS.map(flag => [flag.name, !!pattern[flag.name]]))
      };
    },
    formPayload() {
      const form = {
        license: this.form.license,
        pattern: this.form.pattern,
        risk: this.form.risk,
        packname: this.form.packname
      };
      for (const flag of PATTERN_FLAGS) if (this.form[flag.name]) form[flag.name] = '1';
      return form;
    },
    async loadMatchCount() {
      try {
        const res = await this.ua.get(`/licenses/pattern/${this.pattern.id}/match_count.json`);
        if (!res.isSuccess) throw new Error(`HTTP ${res.statusCode}`);
        this.matchCount = await res.json();
      } catch (_error) {
        this.matchCountError = 'Could not load match count.';
      }
    },
    onClosestLoaded(closest) {
      this.closest = closest;
      if (closest === null && this.activeTab === 'closest') this.activeTab = 'edit';
    },
    setActiveTab(tab) {
      if (tab === 'closest' && this.closest === null) return;
      this.activeTab = tab;
    },
    async onSubmit(event) {
      if (!this.inline) return;
      event.preventDefault();
      if (this.isNew) return;
      this.error = null;
      this.saving = true;
      try {
        const res = await this.ua.post(`/licenses/pattern/${this.pattern.id}.json`, {form: this.formPayload()});
        if (!res.isSuccess) {
          const data = await res.json().catch(() => ({}));
          throw new Error(data.error || `Pattern update failed with HTTP ${res.statusCode}`);
        }
        this.$emit('saved');
      } catch (error) {
        this.error = error.message;
      } finally {
        this.saving = false;
      }
    },
    async onDelete() {
      if (!window.confirm('Sure to delete pattern?')) return;
      this.error = null;
      this.saving = true;
      try {
        const res = await this.ua.delete(`/licenses/remove_pattern/${this.pattern.id}`);
        if (!res.isSuccess) throw new Error('Failed to delete pattern.');
        if (this.inline) this.$emit('deleted');
        else window.location = '/licenses';
      } catch (error) {
        this.error = error.message;
      } finally {
        this.saving = false;
      }
    }
  },
  watch: {
    pattern(pattern) {
      this.form = this.formFromPattern(pattern);
      this.activeTab = 'edit';
      this.closest = null;
      this.matchCount = null;
      this.matchCountError = null;
      this.results = this.suggestions;
      this.licenseFocused = false;
      if (!this.isNew && this.showMatchCount) this.loadMatchCount();
    }
  }
};
</script>

<style scoped>
.edit-pattern-match-count {
  min-height: 1.5rem;
}
.edit-pattern-hidden {
  display: none;
}
.pattern-editor-tabs {
  border-bottom: 1px solid var(--cavil-border);
  display: flex;
  gap: 4px;
  margin-bottom: 16px;
}
.pattern-editor-tab {
  align-items: center;
  background: transparent;
  border: 1px solid transparent;
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  color: var(--cavil-fg-muted);
  cursor: pointer;
  display: inline-flex;
  font-size: 13px;
  font-weight: 500;
  gap: 6px;
  line-height: 1;
  margin-bottom: -1px;
  padding: 8px 14px;
  transition:
    background-color 0.15s,
    color 0.15s;
}
.pattern-editor-tab:hover:not(:disabled):not(.active) {
  background: var(--cavil-canvas-tint);
  color: var(--cavil-fg);
}
.pattern-editor-tab.active {
  background: var(--cavil-canvas);
  border-color: var(--cavil-border);
  color: var(--cavil-fg);
  font-weight: 600;
}
.pattern-editor-tab:disabled {
  color: var(--cavil-fg-disabled);
  cursor: not-allowed;
}
.pattern-editor-tab-badge {
  background: var(--cavil-accent-bg);
  border-radius: 10px;
  color: var(--cavil-accent);
  font-size: 11px;
  font-weight: 600;
  margin-left: 2px;
  padding: 1px 7px;
}
.pattern-editor-tab:disabled .pattern-editor-tab-badge {
  background: var(--cavil-neutral-bg);
  color: var(--cavil-fg-disabled);
}
.pattern-editor-tab-pane {
  display: none;
}
.pattern-editor-tab-pane.is-active {
  display: block;
}
.pattern-editor-actions {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}
.del-pattern {
  margin-left: 0.25rem;
}
.pattern-editor-inline {
  background: var(--cavil-canvas);
}
.pattern-editor-autocomplete-anchor {
  position: relative;
}
.autocomplete-container {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 6px;
  box-shadow: 0 8px 24px rgba(var(--cavil-neutral-rgb), 0.2);
  cursor: pointer;
  left: 0;
  margin: 4px 0 0;
  padding: 4px 0;
  position: absolute;
  right: 0;
  z-index: 1000;
}
.autocomplete {
  max-height: 220px;
  overflow-x: hidden;
  overflow-y: auto;
}
.autocomplete-item {
  color: var(--cavil-fg);
  font-size: 14px;
  padding: 6px 14px;
}
.autocomplete-item:hover {
  background-color: var(--cavil-canvas-subtle);
  color: var(--cavil-fg);
}
</style>
