<template>
  <div
    class="modal fade"
    ref="modal"
    id="globProposalModal"
    tabindex="-1"
    aria-labelledby="globProposalModalLabel"
    aria-hidden="true"
  >
    <div class="modal-dialog">
      <div class="modal-content">
        <div class="modal-header">
          <h5 class="modal-title" id="globProposalModalLabel">{{ create ? 'Add ignore glob' : 'Propose ignore glob' }}</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
        </div>
        <div class="modal-body">
          <p class="glob-proposal-help">
            {{ create ? 'Add' : 'Propose' }} a file path glob to exclude matching files from license scanning
            system-wide<template v-if="create"> right away</template>. Use
            <code>*</code> for the version segment so it applies to future versions of the package.
          </p>
          <form @submit.prevent="onSubmit">
            <div class="mb-3">
              <label for="glob-proposal-input" class="col-form-label">Glob</label>
              <input v-model="glob" ref="input" id="glob-proposal-input" class="form-control glob-proposal-input" />
            </div>
            <div v-if="!create" class="mb-3">
              <label for="glob-proposal-reason" class="col-form-label">Reason</label>
              <textarea v-model="reason" id="glob-proposal-reason" class="form-control" rows="3"></textarea>
            </div>
          </form>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>
          <button
            @click="onSubmit"
            type="button"
            id="glob-proposal-submit"
            class="btn btn-primary"
            :disabled="glob.trim() === ''"
          >
            {{ create ? 'Add Ignore Glob' : 'Propose Ignore Glob' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import {Modal} from 'bootstrap';

export default {
  name: 'GlobProposalModal',
  emits: ['submit'],
  data() {
    return {glob: '', reason: '', create: false, modal: null};
  },
  beforeUnmount() {
    if (this.modal) {
      this.modal.dispose();
      this.modal = null;
    }
  },
  methods: {
    open({glob = '', reason = '', create = false} = {}) {
      this.glob = glob;
      this.reason = reason;
      this.create = create;
      if (!this.modal) this.modal = Modal.getOrCreateInstance(this.$refs.modal);
      this.modal.show();

      // The glob is pre-filled from the file path, which is almost always longer than the field.
      // The part worth editing is the tail (the filename), so once the modal has shown, focus the
      // input and put the cursor at the end - which also scrolls the field to reveal that tail.
      this.$refs.modal.addEventListener(
        'shown.bs.modal',
        () => {
          const input = this.$refs.input;
          input.focus();
          const end = input.value.length;
          input.setSelectionRange(end, end);
        },
        {once: true}
      );
    },
    hide() {
      if (this.modal) this.modal.hide();
    },
    onSubmit() {
      const glob = this.glob.trim();
      if (glob === '') return;
      this.$emit('submit', {glob, reason: this.reason.trim()});
      this.hide();
    }
  }
};
</script>

<style scoped>
.glob-proposal-help {
  color: var(--cavil-fg-muted);
  font-size: 13px;
}
.glob-proposal-help code {
  background: var(--cavil-tint-3);
  border-radius: 4px;
  padding: 0 4px;
}
.glob-proposal-input {
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', monospace;
}
</style>
