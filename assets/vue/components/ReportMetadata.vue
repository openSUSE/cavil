<template>
  <LegalLoading v-if="pkgName === null" message="Reviewing package information..." />
  <div v-else>
    <section class="report-form">
      <header :class="['report-form-head', pkgRisk !== null && `is-${riskTone}`]">
        <span class="report-form-avatar" aria-hidden="true">
          <span v-if="formatIcon !== null" class="cavil-package-format-icon"><i :class="formatIcon"></i></span>
          <i v-else class="fa-solid fa-box-open"></i>
        </span>
        <div class="report-form-title">
          <h2 class="report-metadata-name">
            <a :href="searchUrl" target="_blank"><PackageName :name="pkgName" :family="pkgFamily" /></a>
            <copyable-text :value="String(pkgId)" class="report-metadata-id" title="Click to copy ID" id="pkg-id"
              >#{{ pkgId }}</copyable-text
            >
          </h2>
          <p v-if="pkgSummary !== null" id="pkg-summary" class="report-metadata-summary">{{ pkgSummary }}</p>
        </div>
        <div v-if="pkgRisk !== null" id="report-risk" class="report-risk">
          <span class="report-risk-text">
            <span class="report-risk-label">Risk <HelpButton label="Risk" @click="$refs.riskHelp.open()" /></span>
            <span class="report-risk-description">{{ riskDescription }}</span>
          </span>
          <span class="report-risk-grade">
            <svg viewBox="0 0 40 48" aria-hidden="true">
              <path
                class="report-risk-shield-ledge"
                d="M20 2 L37 8 V21 C37 32 30 40 20 44 C10 40 3 32 3 21 V8 Z"
                transform="translate(0 2)"
              />
              <path class="report-risk-shield-base" d="M20 2 L37 8 V21 C37 32 30 40 20 44 C10 40 3 32 3 21 V8 Z" />
              <path class="report-risk-shield-facet" d="M20 2 L37 8 V21 C37 32 30 40 20 44 Z" />
              <path
                class="report-risk-shield-rim"
                d="M20 6.5 L33.5 11.3 V21 C33.5 30 27.8 36.4 20 39.7 C12.2 36.4 6.5 30 6.5 21 V11.3 Z"
              />
            </svg>
            <strong>{{ pkgRisk }}</strong>
          </span>
        </div>
      </header>
      <dl class="report-metadata-list">
        <div id="report-license" class="report-form-field">
          <dt>
            License
            <HelpButton label="License" @click="$refs.licenseHelp.open()" />
          </dt>
          <dd id="pkg-declarations" :class="{'metadata-declarations-named': namedDeclarations}">
            <div v-for="(d, index) in declarations" :key="index" class="metadata-declaration">
              <span v-if="namedDeclarations" class="metadata-declaration-name">{{ d.showName ? d.name : '' }}</span>
              <span v-if="d.license_html !== null" v-html="d.license_html"></span>
              <span v-else class="metadata-declaration-undeclared">No license declared</span>
              <a :href="d.fileUrl" class="metadata-declaration-file" target="_blank">{{ displayName(d.file) }}</a>
              <span class="metadata-declaration-format">{{ d.format }}</span>
            </div>
            <span v-if="declarations.length === 0" class="metadata-declaration-undeclared">No license declared</span>
          </dd>
        </div>
      </dl>
      <dl v-if="pkgUrl !== null || links.length > 0 || relatedReviews > 0" class="report-metadata-list">
        <div v-if="pkgUrl !== null" class="report-form-field is-wide">
          <dt>URL</dt>
          <dd id="pkg-url">
            <a :href="pkgUrl" target="_blank">{{ pkgUrl }}</a>
          </dd>
        </div>
        <div v-if="links.length > 0" class="report-form-field">
          <dt>{{ links.length === 1 ? 'Link' : 'Links' }}</dt>
          <dd id="pkg-link" class="report-metadata-links">
            <span
              v-for="(link, index) in links"
              :key="index"
              :class="['report-metadata-link', {'is-closed': !link.active}]"
              :title="link.active ? null : 'Closed'"
            >
              <ExternalLink :link="link" />
            </span>
          </dd>
        </div>
        <div v-if="relatedReviews > 0" class="report-form-field">
          <dt>Actions</dt>
          <dd>
            <a id="related-reviews" :href="`/search?q=${encodeURIComponent(externalLink)}`" target="_blank">
              {{ relatedReviews === 1 ? '1 related review' : `${relatedReviews} related reviews` }}
            </a>
          </dd>
        </div>
      </dl>
      <dl class="report-metadata-list">
        <div id="report-documents-field" class="report-form-field is-wide">
          <dt>Documents <HelpButton label="Documents" @click="$refs.documentsHelp.open()" /></dt>
          <dd id="report-documents">
            <report-documents :pkg-id="pkgId" :documents="derivedDocuments" @error="notifyError" />
          </dd>
        </div>
        <div v-if="checkoutUrl !== null" class="report-form-field">
          <dt>Checkout</dt>
          <dd id="checkout-url">
            <a :href="checkoutUrl" target="_blank">{{ pkgChecksum }}</a>
          </dd>
        </div>
        <div v-if="pkgVersion !== null" class="report-form-field">
          <dt>Version</dt>
          <dd id="pkg-version">{{ pkgVersion }}</dd>
        </div>
      </dl>
      <dl class="report-metadata-list">
        <div v-if="productsHtml !== null" :class="['report-form-field', {'is-wide': pkgEphemeral !== true}]">
          <dt>Products</dt>
          <dd id="pkg-products" v-html="productsHtml"></dd>
        </div>
        <div v-if="state !== null" class="report-form-field">
          <dt>State</dt>
          <dd>
            <span id="pkg-state" class="badge" :class="stateBadgeClass">{{ state }}</span>
            <a
              v-if="canViewAudit"
              :href="`/audit?filter=${encodeURIComponent(pkgName)}`"
              class="metadata-history-link"
              target="_blank"
              >History</a
            >
          </dd>
        </div>
        <div id="report-embargo" :class="['report-form-field', {'is-flagged': pkgEmbargoed === true}]">
          <dt>Embargoed <HelpButton label="Embargoed" @click="$refs.embargoHelp.open()" /></dt>
          <dd v-if="pkgEmbargoed === true" id="pkg-embargoed" title="Package is embargoed">
            <i class="fa-solid fa-lock" aria-hidden="true"></i>Yes
          </dd>
          <dd v-else id="pkg-embargoed">No</dd>
        </div>
        <div v-if="pkgEphemeral === true" class="report-form-field is-flagged">
          <dt>Ephemeral</dt>
          <dd id="pkg-ephemeral" title="One-off review, not part of the legal backlog">
            <i class="fa-solid fa-hourglass-half" aria-hidden="true"></i>One-off review
            <span v-if="ephemeralDelete !== ''" class="report-ephemeral-hint">deleted {{ ephemeralDelete }}</span>
          </dd>
        </div>
      </dl>
      <dl
        v-if="pkgPriority !== null || pkgShortname !== null || unpackedFiles > 0"
        class="report-metadata-list is-secondary"
      >
        <div v-if="unpackedFiles > 0" class="report-form-field is-wide">
          <dt>Unpacked</dt>
          <dd id="unpacked-files">
            {{ unpackedFilesLabel }}
            <small>{{ unpackedSize }}</small>
          </dd>
        </div>
        <div v-if="pkgShortname !== null" class="report-form-field">
          <dt>Shortname</dt>
          <dd id="pkg-shortname">{{ pkgShortname }}</dd>
        </div>
        <div v-if="pkgPriority !== null" class="report-form-field">
          <dt>Priority</dt>
          <dd id="pkg-priority">{{ pkgPriority }}</dd>
        </div>
      </dl>
      <footer v-if="timelineSteps.length > 0" id="review-timeline" class="report-form-foot">
        <ReviewTimeline :steps="timelineSteps" />
      </footer>
    </section>
    <HelpDialog ref="licenseHelp" title="License">
      <p>
        This is the license the packager declared. In a spec file it covers the whole package, and a subpackage with a
        different license gets its own line.
      </p>
      <div class="help-example">
        <div class="help-example-file">{{ specFile ?? 'package.spec' }}</div>
        <pre>
<strong>License:</strong>  GPL-2.0-or-later

%package -n libfoo1
<strong>License:</strong>  LGPL-2.1-or-later</pre>
      </div>
      <p>
        A Dockerfile or Helm chart is different: its license covers only that one file, not the container or chart built
        from it.
      </p>
      <p>Cavil does not check what is declared, so compare it with what the report below found.</p>
    </HelpDialog>
    <HelpDialog ref="riskHelp" title="Risk">
      <p>
        This is the highest risk of anything Cavil found in the source, so a single risky file raises the whole package.
      </p>
      <div class="help-example">
        <div class="help-example-file">Risk levels</div>
        <!-- prettier-ignore -->
        <pre><component
          :is="level.risk === pkgRisk ? 'strong' : 'span'"
          v-for="level in RISK_SCALE"
          :key="level.risk"
        >{{ level.line }}</component></pre>
      </div>
      <p>It shows where to look closer, not whether the package is acceptable.</p>
    </HelpDialog>
    <HelpDialog ref="documentsHelp" title="Documents">
      <p>These files are made from the report on request. The first click builds one, the next one downloads it.</p>
      <div class="help-example">
        <div class="help-example-file">Documents</div>
        <pre>
<strong>SBOM</strong>     the package and its licenses, in the SPDX format
<strong>Notice</strong>   the licenses and copyright lines found in the source
<strong>Dossier</strong>  the report's evidence in one file, to upload to an AI assistant</pre>
      </div>
    </HelpDialog>
    <HelpDialog ref="embargoHelp" title="Embargoed">
      <p>
        An embargoed package fixes a security issue that is not public yet. AI tools that connect to Cavil cannot see
        it.
      </p>
      <p>The Dossier still works, so only hand it to an AI you are allowed to use for embargoed work.</p>
    </HelpDialog>
    <section v-if="notice !== null" id="review-information" class="review-information-card">
      <header class="review-information-card-bar">
        <i class="fa-solid fa-caret-right"></i>
        <span>why this needs review</span>
        <HelpButton label="Why this needs review" @click="$refs.reviewHelp.open()" />
      </header>
      <HelpDialog ref="reviewHelp" title="Why this needs review">
        <p>
          Cavil compares every new package with earlier accepted versions of the same software. This box says what it
          found, and why the package was or was not accepted automatically.
        </p>
        <div class="help-example">
          <div class="help-example-file">Example</div>
          <pre>
Diff to closest match <strong>573150</strong>

  New licenses (by risk)
    5  GPL-3.0-or-later</pre
          >
        </div>
        <p>
          The number links to the closest earlier report. Below it is only what changed since then, like new licenses
          with their risk or text Cavil could not match, which is usually the best place to start.
        </p>
        <p>
          "Limitation noted" means a reviewer set a condition on an earlier version, so every new version needs a human
          review until the limitation is removed.
        </p>
      </HelpDialog>
      <!-- prettier-ignore -->
      <pre class="review-information-card-body"><span
        v-for="(segment, index) in noticeSegments"
        :key="index"
      ><a
        v-if="segment.isReportId"
        :href="`/reviews/details/${segment.text}`"
        target="_blank"
        rel="noopener"
      >{{ segment.text }}</a><template v-else>{{ segment.text }}</template></span></pre>
    </section>
    <a
      v-if="aiRecommendation !== null"
      id="ai-recommendation"
      class="ai-recommendation"
      :href="`#note-${aiRecommendation.id}`"
      @click="seekSameNote"
    >
      <svg
        class="ai-recommendation-avatar"
        :class="robotQuirk && `ai-recommendation-${robotQuirk}`"
        viewBox="0 0 32 32"
        aria-hidden="true"
      >
        <path class="ai-recommendation-wave" d="M14 0.54 A4 4 0 0 0 12 4 M18 0.54 A4 4 0 0 1 20 4" />
        <path class="ai-recommendation-wave" d="M12.75 -1.63 A6.5 6.5 0 0 0 9.5 4 M19.25 -1.63 A6.5 6.5 0 0 1 22.5 4" />
        <g class="ai-recommendation-stalk">
          <line x1="16" y1="4" x2="16" y2="9" />
          <circle class="ai-recommendation-antenna" cx="16" cy="4" r="2" />
        </g>
        <rect class="ai-recommendation-ear" x="3" y="15" width="3" height="6" rx="1.5" />
        <rect class="ai-recommendation-ear" x="26" y="15" width="3" height="6" rx="1.5" />
        <rect class="ai-recommendation-head" x="6" y="9" width="20" height="17" rx="5" />
        <g class="ai-recommendation-eyes" @animationiteration="pickRobotQuirk">
          <circle cx="12.5" cy="16" r="2" />
          <circle cx="19.5" cy="16" r="2" />
        </g>
        <path class="ai-recommendation-mouth" d="M12.5 21 q3.5 2.2 7 0" />
      </svg>
      <div class="ai-recommendation-bubble">
        <div class="ai-recommendation-speech">
          <div class="ai-recommendation-says">
            {{ aiRecommendation.before }}
            <strong :class="`ai-recommendation-${aiRecommendation.tone}`">{{ aiRecommendation.phrase }}</strong>
            {{ aiRecommendation.after }}
          </div>
          <div class="ai-recommendation-meta">
            {{ aiRecommendation.bot ? 'Sent' : 'Asked' }} by {{ aiRecommendation.author_login }} &middot;
            <span :title="aiRecommendation.timestamp">{{ aiRecommendation.created }}</span>
          </div>
        </div>
        <span class="ai-recommendation-more">Read note <i class="fa-solid fa-arrow-down"></i></span>
      </div>
    </a>
    <cavil-notice-panel
      v-if="incompleteCheckout.length > 0"
      id="incomplete-checkout"
      icon="fa-solid fa-triangle-exclamation"
      :items="incompleteCheckout"
      title="Checkout may be incomplete"
      tone="warning"
    />
    <div class="report-review-box">
      <section v-if="tags.length > 0 || canEditTags" id="package-tags" class="package-tags-bar">
        <span class="package-tags-label">Tags</span>
        <div id="pkg-tags" class="package-tags-body">
          <TagInput
            v-if="canEditTags"
            :model-value="tags"
            :suggestions="knownTags"
            data-key="pkg-tags"
            @update:model-value="onTagsChanged"
          />
          <div v-else class="package-tags-readonly">
            <span
              v-for="tag in tags"
              :key="tag"
              class="report-note-tag"
              :class="{'report-cve-tag': isCve(tag)}"
              :title="`Tag: ${tag}`"
              >{{ tag }}</span
            >
          </div>
        </div>
      </section>
      <form class="metadata-review-form" id="pkg-review" @submit.prevent>
        <div class="metadata-review-editor">
          <CommentEditor
            ref="commentEditor"
            v-model="result"
            label="Comment"
            :placeholder="canReview ? 'Reviewed ok' : ''"
            :read-only="!canReview"
          >
            <template #actions v-if="canReview && templates.length > 0">
              <TemplatePicker
                :manage-url="hasAdminRole === true ? manageTemplatesUrl : null"
                :templates="templates"
                @select="insertTemplate"
              />
            </template>
            <template #footer v-if="selectedButtonId !== null">
              <div
                :class="['metadata-review-status', `is-${selectedButtonId}`]"
                role="status"
                aria-live="polite"
                aria-atomic="true"
              >
                <i class="fa-solid fa-circle-check metadata-review-status-icon" aria-hidden="true"></i>
                <strong>Review finalized</strong>
                <span v-if="reviewingUser !== null || reviewed !== null" class="metadata-review-status-detail">
                  <template v-if="reviewingUser !== null">
                    by {{ reviewingUser }}
                    <span v-if="pkgAiAssisted" class="ai-assisted-badge">
                      (with AI Assistant <i class="fa-solid fa-robot" aria-hidden="true"></i>)
                    </span>
                  </template>
                  <template v-if="reviewingUser !== null && reviewed !== null"> &middot; </template>
                  <template v-if="reviewed !== null">{{ reviewed }}</template>
                </span>
              </div>
            </template>
          </CommentEditor>
        </div>
        <div v-if="canReview" class="metadata-review-actions">
          <div class="metadata-review-actions-group">
            <!-- One accept button; the server derives acceptable vs acceptable_by_lawyer from the
                 reviewer's capability, so a non-lawyer can never post a lawyer sign-off.

                 The pair doubles as a live indicator of the current decision: the button matching the
                 stored state stays solid, while the alternative recedes to an outline but stays fully
                 clickable so the reviewer can still switch their mind. -->
            <button
              v-for="button in reviewButtons"
              :key="button.id"
              type="button"
              :class="[
                'btn',
                buttonClass(button),
                {'is-decision-current': selectedButtonId === button.id, 'is-decision-flash': flashId === button.id}
              ]"
              :id="button.id"
              :name="button.id"
              :aria-pressed="selectedButtonId === button.id"
              :disabled="submitting"
              @click="submitReview(submitUrl, button.id)"
            >
              <i v-if="submittingId === button.id" class="fa-solid fa-rotate fa-spin" aria-hidden="true"></i>
              {{ button.label }}
            </button>
          </div>
          <div v-if="hasAdminRole === true" class="metadata-review-limitation">
            <label
              :class="{'is-checked': withLimitation}"
              :title="
                limitations.length === 0
                  ? 'Accepting saves your comment as a limitation, so every future version needs a human review'
                  : null
              "
            >
              <input
                v-model="withLimitation"
                type="checkbox"
                class="form-check-input"
                aria-describedby="limitation-effect"
                :disabled="submitting"
                data-limitation-checkbox
                @change="limitationTouched = true"
              />
              With limitation
            </label>
            <!-- prettier-ignore -->
            <span
              v-if="limitationEffect !== null"
              id="limitation-effect"
              :class="['metadata-review-limitation-effect', {'is-removing': limitationEffect.removing}]"
              data-limitation-effect
            >
              <i v-if="limitationEffect.removing" class="fa-solid fa-triangle-exclamation" aria-hidden="true"></i
              >{{ limitationEffect.before }}<span v-for="(origin, index) in limitationEffect.origins" :key="origin.text"
              >{{ index > 0 ? ' and ' : '' }}<a v-if="origin.url" :href="origin.url" target="_blank" rel="noopener"
              >{{ origin.text }}</a><template v-else>{{ origin.text }}</template></span>{{ limitationEffect.after }}
            </span>
          </div>
          <button
            v-if="hasAdminRole === true"
            type="button"
            :class="['btn', reindexBtnVariant, 'metadata-review-actions-secondary']"
            :title="reindexTitle"
            :disabled="reindexBusy || rebuildPending"
            id="reindex_button"
            @click="reindex"
          >
            <i v-if="reindexBusy || rebuildPending" class="fa-solid fa-rotate fa-spin" aria-hidden="true"></i>
            {{ reindexBusy || rebuildPending ? 'Reindexing…' : 'Reindex' }}
          </button>
        </div>
      </form>
    </div>
    <cavil-notice-panel
      v-if="noticeFile !== null"
      id="spec-legal-review-notices"
      icon="fa-solid fa-user-pen"
      title="Legal review notices from packagers"
      :note="legalReviewNotices.length > 0 ? null : 'None'"
    >
      <template #help>
        <p>
          Packagers can leave a note for the legal reviewer as a comment in the packaging file. It shows up in this
          panel.
        </p>
        <div class="help-example">
          <div class="help-example-file">{{ noticeFile }}</div>
          <pre>
# <strong>Legal-Review-Notice:</strong> The bundled libfoo sources are never built,
#                      the system libfoo is used instead.</pre
          >
        </div>
        <p>
          Use it to explain something the report flags, like bundled code that is never shipped, or which license was
          chosen for dual-licensed code.
        </p>
        <p>Cavil does not check what a notice says, so treat it as the packager's explanation, not as a fact.</p>
      </template>
      <template v-if="legalReviewNotices.length > 0" #default>
        <ul class="cavil-notice-list">
          <!-- eslint-disable-next-line vue/no-v-for-template-key -->
          <template v-for="(text, index) in legalReviewNotices" :key="index">
            <li
              :class="['cavil-notice-item', {'legal-review-notice-clamped': noticeClamped(text, index)}]"
              v-text="text"
            ></li>
            <li v-if="noticeLines(text) > NOTICE_PREVIEW_LINES" class="list-more-toggle">
              <button type="button" @click="toggleNotice(index)">
                <i :class="noticesExpanded.has(index) ? 'fa-solid fa-chevron-up' : 'fa-solid fa-chevron-down'"></i>
                {{ noticesExpanded.has(index) ? 'Show less' : `Show full notice (${noticeLines(text)} lines)` }}
              </button>
            </li>
          </template>
        </ul>
      </template>
    </cavil-notice-panel>
    <cavil-notice-panel
      v-if="legalDocuments !== null"
      id="legal-documents"
      icon="fa-solid fa-scale-balanced"
      title="Legal documents"
      :note="documentsNote"
    >
      <template #help>
        <p>
          These are the package's own license files, like LICENSE, COPYING or NOTICE. License files in folders for
          bundled code, tests, examples or documentation are left out, they show up in the report below.
        </p>
        <ul class="cavil-notice-list help-example">
          <li v-for="example in DOCUMENT_EXAMPLES" :key="example.path" class="cavil-notice-item legal-document-item">
            <span class="legal-document-path">{{ example.path }}</span>
            <span class="legal-document-lines">
              <span class="legal-document-tally">{{ documentTally(example) }}</span>
              <span class="legal-document-meter" aria-hidden="true"
                ><i
                  v-for="block in 5"
                  :key="block"
                  :class="['legal-document-block', {'is-covered': block <= documentBlocks(example)}]"
                ></i
              ></span>
            </span>
          </li>
        </ul>
        <p>
          The bar shows how much of each file Cavil recognises as known license text. Anything else can be harmless,
          like a different copyright line, or extra terms, like a ban on commercial use, so open the file and read the
          parts Cavil does not know.
        </p>
      </template>
      <template v-if="documents.length > 0" #default>
        <ul class="cavil-notice-list">
          <li v-for="document in shownDocuments" :key="document.path" class="cavil-notice-item legal-document-item">
            <a :href="document.url" target="_blank" rel="noopener" class="legal-document-path"
              ><FilePath :path="document.path"
            /></a>
            <span class="legal-document-lines" :title="documentShare(document)">
              <!-- Absolute, not a percentage: 15 novel lines in a 312-line BSD file round away to "5%" -->
              <span class="legal-document-tally">{{ documentTally(document) }}</span>
              <span class="legal-document-meter" aria-hidden="true"
                ><i
                  v-for="block in 5"
                  :key="block"
                  :class="['legal-document-block', {'is-covered': block <= documentBlocks(document)}]"
                ></i
              ></span>
            </span>
          </li>
          <ListMoreToggle
            v-if="documents.length > DOCUMENTS_PREVIEW"
            :expanded="documentsExpanded"
            :hidden="documents.length - DOCUMENTS_PREVIEW"
            :preview="DOCUMENTS_PREVIEW"
            @toggle="documentsExpanded = !documentsExpanded"
          />
        </ul>
      </template>
    </cavil-notice-panel>
    <cavil-notice-panel v-if="specFile !== null" id="copied-files" icon="fa-regular fa-copy" title="Copied files">
      <template #help>
        <p>
          These are the files the spec file adds to the finished package for users to read: documentation marked
          <code>%doc</code> and license texts marked <code>%license</code>.
        </p>
        <div class="help-example">
          <div class="help-example-file">{{ specFile }}</div>
          <pre>
%files
<strong>%license</strong> COPYING
<strong>%doc</strong> README.md NEWS</pre
          >
        </div>
        <p>
          Many licenses require their text to be passed on with the software, so "no license text copied" deserves a
          closer look.
        </p>
        <p>
          The list can be incomplete when the spec file uses macros or installs files in other ways, so check the spec
          file when in doubt.
        </p>
      </template>
      <dl class="cavil-notice-definition-list">
        <dt>%doc</dt>
        <dd v-if="copiedFiles['%doc'] !== null">{{ copiedFiles['%doc'] }}</dd>
        <dd v-else class="text-muted">none</dd>
        <dt>%license</dt>
        <dd v-if="copiedFiles['%license'] !== null">{{ copiedFiles['%license'] }}</dd>
        <dd v-else>
          <span class="cavil-meta-badge cavil-meta-badge-info" data-no-license-text>no license text copied</span>
        </dd>
      </dl>
    </cavil-notice-panel>
    <ToastNotifier ref="toaster" />
  </div>
</template>

<script>
import CavilNoticePanel from './CavilNoticePanel.vue';
import CommentEditor from './CommentEditor.vue';
import CopyableText from './CopyableText.vue';
import ExternalLink from './ExternalLink.vue';
import FilePath from './FilePath.vue';
import HelpButton from './HelpButton.vue';
import HelpDialog from './HelpDialog.vue';
import LegalLoading from './LegalLoading.vue';
import ListMoreToggle from './ListMoreToggle.vue';
import PackageName from './PackageName.vue';
import ReportDocuments from './ReportDocuments.vue';
import ReviewTimeline from './ReviewTimeline.vue';
import TagInput from './TagInput.vue';
import TemplatePicker from './TemplatePicker.vue';
import ToastNotifier from './ToastNotifier.vue';
import {displayName, fileViewUrl, productLink, setupPopoverDelayed} from '../helpers/links.js';
import {findPlaceholders} from '../helpers/placeholders.js';
import {RISK_LEVELS, riskBadgeClass, riskName} from '../helpers/riskLevels.js';
import Refresh from '../mixins/refresh.js';
import UserAgent from '@mojojs/user-agent';
import moment from 'moment';

const AI_VERDICT_MESSAGES = {
  ACCEPT: {tone: 'success', before: 'I recommend', phrase: 'accepting', after: 'this review.'},
  'NEEDS HUMAN REVIEW': {
    tone: 'attention',
    before: 'This review',
    phrase: 'needs a closer look',
    after: 'from a human.'
  },
  REJECT: {tone: 'danger', before: 'I recommend', phrase: 'rejecting', after: 'this review.'}
};

const chatTime = time => ({
  created: time.calendar({
    sameDay: '[today at] HH:mm',
    lastDay: '[yesterday]',
    lastWeek: 'dddd',
    sameElse: 'MMM D, YYYY'
  }),
  timestamp: time.format('YYYY-MM-DD HH:mm')
});

const DOCUMENT_EXAMPLES = [
  {path: 'LICENSE', lines: 21, unexplained: 0},
  {path: 'NOTICE', lines: 14, unexplained: 6}
];
// Only these declaration formats can carry a Legal-Review-Notice comment
const NOTICE_FORMATS = ['spec', 'dockerfile', 'helm'];
const RISK_EXAMPLES = {
  1: 'CC0-1.0, Unlicense',
  2: 'MIT, BSD-3-Clause, Apache-2.0',
  3: 'LGPL-2.1-or-later, MPL-2.0',
  4: 'GPL-2.0-only, GPL-3.0-or-later',
  5: 'AGPL-3.0-or-later, BSD-4-Clause',
  6: 'SSPL-1.0',
  7: 'CC-BY-NC-4.0, JSON',
  8: 'a new license nobody has rated yet',
  9: 'text Cavil could not match to a license'
};
// The unrated and unknown levels sit apart from the rated ones, as in the docs
const RISK_SCALE = Object.entries(RISK_EXAMPLES).map(([risk, examples]) => ({
  risk,
  line: `${risk}  ${(RISK_LEVELS[risk] ?? 'Unknown').padEnd(25)}${examples}\n${risk === '7' ? '\n' : ''}`
}));
const FORMAT_ICONS = {
  spec: 'fa-brands fa-suse',
  debian: 'fa-brands fa-debian',
  kiwi: 'fa-solid fa-kiwi-bird',
  dockerfile: 'fa-brands fa-docker',
  helm: 'fa-solid fa-dharmachakra',
  obsprj: 'fa-solid fa-industry',
  npm: 'fa-brands fa-npm',
  cargo: 'fa-brands fa-rust',
  pypi: 'fa-brands fa-python',
  maven: 'fa-brands fa-java',
  golang: 'fa-brands fa-golang',
  composer: 'fa-brands fa-php',
  gem: 'fa-solid fa-gem',
  nuget: 'fa-brands fa-microsoft'
};

export default {
  name: 'ReportMetadata',
  components: {
    CavilNoticePanel,
    CommentEditor,
    CopyableText,
    ExternalLink,
    FilePath,
    HelpButton,
    HelpDialog,
    LegalLoading,
    ListMoreToggle,
    PackageName,
    ReportDocuments,
    ReviewTimeline,
    TagInput,
    TemplatePicker,
    ToastNotifier
  },
  mixins: [Refresh],
  emits: ['limitations-changed', 'reindex-queued'],
  data() {
    return {
      externalLink: null,
      relatedReviews: 0,
      aiRecommendation: null,
      robotQuirk: null,
      checkoutUrl: null,
      copiedFiles: {'%doc': null, '%license': null},
      timestamps: null,
      declarations: [],
      DOCUMENTS_PREVIEW: 10,
      documentsExpanded: false,
      legalDocuments: null,
      fasttrackUrl: `/reviews/fasttrack_package/${this.pkgId}`,
      legalReviewNotices: [],
      DOCUMENT_EXAMPLES,
      RISK_SCALE,
      NOTICE_PREVIEW_LINES: 4,
      noticesExpanded: new Set(),
      limitations: [],
      limitationTouched: false,
      manageTemplatesUrl: '/settings/comment-templates',
      notice: null,
      pkgAiAssisted: false,
      pkgChecksum: null,
      pkgEmbargoed: false,
      pkgEphemeral: false,
      tags: [],
      knownTags: [],
      canEditTags: false,
      canViewAudit: false,
      ephemeralDelete: '',
      incompleteCheckout: [],
      pkgFamily: null,
      pkgName: null,
      pkgPriority: null,
      pkgRisk: null,
      pkgShortname: null,
      pkgSummary: null,
      pkgUrl: null,
      pkgVersion: null,
      productsHtml: null,
      refreshDelay: 30000,
      refreshUrl: `/reviews/meta/${this.pkgId}`,

      // Seeded from the page render so the button has an answer before the first refresh lands, and kept
      // current from there on: a rebuild takes the package past the patterns that lit it up, and patterns
      // created while the page sits open light it up again
      newPatterns: this.shouldReindex,
      reindexBusy: false,
      reindexFailed: false,
      reindexing: false,
      reindexQueued: false,
      links: [],
      result: '',
      reviewed: null,
      reviewingUser: null,
      reviewUrl: `/reviews/review_package/${this.pkgId}`,
      searchUrl: null,
      derivedDocuments: null,
      state: null,
      submitting: false,
      submittingId: null,
      flashId: null,
      flashTimer: null,
      templates: [],
      unpackedFiles: 0,
      unpackedSize: 'n/a',
      withLimitation: false
    };
  },
  computed: {
    namedDeclarations() {
      return this.declarations.some(d => d.showName);
    },
    formatIcon() {
      return FORMAT_ICONS[this.declarations[0]?.format] ?? null;
    },
    specFile() {
      const declaration = this.declarations.find(d => d.format === 'spec');
      return declaration === undefined ? null : displayName(declaration.file);
    },
    noticeFile() {
      const declaration = this.declarations.find(d => NOTICE_FORMATS.includes(d.format));
      return declaration === undefined ? null : displayName(declaration.file);
    },
    canReview() {
      if (this.hasAdminRole === true) return true;
      return this.hasManagerRole === true && (this.state === 'new' || this.state === 'acceptable');
    },

    documents() {
      return this.legalDocuments?.documents ?? [];
    },

    shownDocuments() {
      return this.documentsExpanded ? this.documents : this.documents.slice(0, this.DOCUMENTS_PREVIEW);
    },

    documentsNote() {
      const dropped = this.legalDocuments?.dropped ?? 0;
      if (dropped > 0) return `${this.count(dropped)} more not listed`;
      return this.documents.length > 0 ? null : 'None';
    },

    // A curator gets accept and reject, a manager only the fasttrack accept
    reviewButtons() {
      if (this.hasAdminRole === true) {
        return [
          {id: 'acceptable', variant: 'btn-success', label: this.hasLawyerRole ? 'Acceptable by Lawyer' : 'Acceptable'},
          {id: 'unacceptable', variant: 'btn-danger', label: 'Unacceptable'}
        ];
      }
      if (this.hasManagerRole === true) return [{id: 'acceptable', variant: 'btn-success', label: 'Acceptable'}];
      return [];
    },
    // Only Accept applies the checkbox, so a change is phrased as what accepting does
    limitationEffect() {
      if (this.hasAdminRole !== true) return null;
      const count = this.limitations.length;
      if (count === 0) {
        if (!this.withLimitation) return null;
        return {
          before:
            this.result.trim() === ''
              ? 'Write the limitation in the comment.'
              : 'Accepting saves your comment as a limitation.'
        };
      }
      if (!this.withLimitation) {
        const what = count === 1 ? 'the limitation' : count === 2 ? 'both limitations' : `all ${count} limitations`;
        const others = [...new Set(this.limitations.map(l => l.package_name).filter(name => name !== this.pkgName))];
        const noted = others.length > 0 ? `, noted for ${others.join(' and ')}` : '';
        return {
          before: `Accepting removes ${what}${noted}. Future versions can be accepted automatically.`,
          removing: true
        };
      }

      const origins = [];
      const seen = new Set();
      for (const {package: id, package_name: name} of this.limitations) {
        if (seen.has(id)) continue;
        seen.add(id);
        const of = name === this.pkgName ? '' : ` of ${name}`;
        if (id === null) origins.push({text: `a deleted review${of}`});
        else if (id === Number(this.pkgId)) origins.push({text: 'this review'});
        else origins.push({text: `review #${id}${of}`, url: `/reviews/details/${id}`});
      }
      return {before: 'Noted in ', origins, after: '.'};
    },
    submitUrl() {
      return this.hasAdminRole === true ? this.reviewUrl : this.fasttrackUrl;
    },
    // Which review button the stored state currently corresponds to (null while the package is still
    // "new"), so the pair can show the decision instead of just firing it
    selectedButtonId() {
      if (this.state === 'acceptable' || this.state === 'acceptable_by_lawyer') return 'acceptable';
      if (this.state === 'unacceptable') return 'unacceptable';
      return null;
    },
    // Notices that refer to an older review name it by id ("Diff to closest
    // match 538922", "Not found any significant difference against 538922",
    // "Limitation noted in 538922", "same license as 538922"). Those ids
    // become links to that report, everything else stays plain text.
    noticeSegments() {
      if (this.notice === null) return [];
      const segments = [];
      const pattern =
        /(?<=Diff to closest match |significant difference against |Limitation noted in |same license as )\d+/g;
      let plainFrom = 0;
      for (const match of this.notice.matchAll(pattern)) {
        segments.push({text: this.notice.slice(plainFrom, match.index)});
        segments.push({text: match[0], isReportId: true});
        plainFrom = match.index + match[0].length;
      }
      segments.push({text: this.notice.slice(plainFrom)});
      return segments;
    },
    unpackedFilesWithSeparator() {
      return this.unpackedFiles.toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
    },

    // The count on its own, so the size can sit beside it as a quiet aside instead of in brackets
    unpackedFilesLabel() {
      return this.unpackedFiles === 1 ? '1 file' : `${this.unpackedFilesWithSeparator} files`;
    },
    // Shown under a "Risk" label
    riskDescription() {
      return riskName(this.pkgRisk).replace(/ Risk$/, '');
    },
    riskTone() {
      const badge = riskBadgeClass(this.pkgRisk);
      return badge.startsWith('text-bg-') ? badge.slice(8) : 'unknown';
    },
    // Fixed order, never sorted by time: every package is reindexed at least weekly, so "indexed" (and anything
    // restamped after the decision) is a last-run time that keeps its place and only shows in the tooltip
    timelineSteps() {
      const t = this.timestamps;
      if (t === null) return [];
      const decided = this.selectedButtonId;
      const step = (label, epoch, again) =>
        again && epoch !== null
          ? {
              label,
              epoch: null,
              done: true,
              title: `Last ${label.toLowerCase()} ${moment(epoch * 1000).format('YYYY-MM-DD HH:mm')}`
            }
          : {label, epoch};
      const redone = epoch => decided !== null && t.reviewed !== null && epoch > t.reviewed;
      const pipeline = [
        step('Requested', t.created, false),
        step('Imported', t.imported, redone(t.imported)),
        step('Unpacked', t.unpacked, redone(t.unpacked)),
        step('Indexed', t.indexed, true),
        decided === null
          ? {label: 'Awaiting review', epoch: null, waiting: true}
          : {
              label: decided === 'acceptable' ? 'Accepted' : 'Rejected',
              epoch: t.reviewed,
              tone: decided === 'acceptable' ? 'success' : 'danger',
              done: true
            }
      ];
      const lastDone = pipeline.findLastIndex(step => step.epoch !== null || step.done);
      const done = pipeline.slice(0, lastDone + 1).filter(step => step.epoch !== null || step.done);
      const extras = [
        this.aiRecommendation === null ? null : {label: 'AI recommended', epoch: this.aiRecommendation.created_epoch},
        t.cleaned === null ? null : {label: 'Cleaned up', epoch: t.cleaned}
      ];
      for (const extra of extras.filter(extra => extra !== null)) {
        const later = done.findIndex(step => step.epoch !== null && step.epoch > extra.epoch);
        done.splice(later === -1 ? done.length : later, 0, extra);
      }
      return [...done, ...pipeline.slice(lastDone + 1).map(step => ({...step, pending: true}))];
    },
    stateBadgeClass() {
      if (this.state === 'new') return 'text-bg-secondary';
      if (this.state === 'acceptable_by_lawyer' || this.state === 'acceptable') return 'text-bg-success';
      return 'text-bg-danger';
    },
    // A rebuild that is already on its way answers the button, so it stops advertising the patterns that
    // rebuild is about to pick up - whoever started it
    rebuildPending() {
      return this.reindexQueued || this.reindexing;
    },
    reindexBtnVariant() {
      if (this.reindexFailed) return 'btn-outline-danger';
      if (this.rebuildPending) return 'btn-outline-secondary';
      return this.newPatterns ? 'btn-outline-primary' : 'btn-outline-secondary';
    },
    reindexTitle() {
      if (this.reindexFailed) return 'Reindex request failed';
      if (this.rebuildPending) return 'Reindex has been requested';
      return this.newPatterns ? 'There are new patterns!' : 'There are no new patterns';
    }
  },
  // Templates barely ever change, so they are fetched once instead of on every metadata refresh
  mounted() {
    if (this.hasAdminRole === true || this.hasManagerRole === true) this.loadTemplates();
  },
  methods: {
    displayName,
    noticeLines(text) {
      return text.split('\n').length;
    },

    noticeClamped(text, index) {
      return this.noticeLines(text) > this.NOTICE_PREVIEW_LINES && !this.noticesExpanded.has(index);
    },

    toggleNotice(index) {
      if (!this.noticesExpanded.delete(index)) this.noticesExpanded.add(index);
    },

    // The browser fires no hashchange for the hash it is already on, so a second click would do nothing
    seekSameNote(event) {
      if (event.currentTarget.hash === window.location.hash) window.dispatchEvent(new HashChangeEvent('hashchange'));
    },
    pickRobotQuirk() {
      const quirks = ['waves', 'wobble', 'double-blink'];
      this.robotQuirk = Math.random() < 1 / 4 ? quirks[Math.floor(Math.random() * quirks.length)] : null;
    },
    insertTemplate(template) {
      this.$refs.commentEditor?.insertTemplate(template.body);
    },

    isCve(tag) {
      return tag === 'CVE';
    },

    onTagsChanged(tags) {
      this.tags = tags;
      this.saveTags();
    },

    async saveTags() {
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.patch(`/reviews/tags/${this.pkgId}`, {form: {tags_json: JSON.stringify(this.tags)}});
      if (!res.isSuccess) this.$refs.toaster?.notify('Failed to save tags', 'danger', 5000);
    },

    async loadKnownTags() {
      const ua = new UserAgent({baseURL: window.location.href});
      const res = await ua.get('/reviews/tags.json');
      if (res.isSuccess) {
        const data = await res.json();
        if (Array.isArray(data.tags)) this.knownTags = data.tags;
      }
    },

    // Never zero and never full below 100%: the case this exists for is a few lines in a large file
    // Filled is coverage, the direction every other meter in the world fills. Marking the deficit
    // instead put amber on the rows that needed reading and lawyers could not decode it.
    documentBlocks(document) {
      if (document.unexplained >= document.lines) return 0;
      return 5 - Math.min(4, Math.ceil((document.unexplained / document.lines) * 5));
    },

    // One annotation on the mark rather than two aligned columns, now that the mark is what gets scanned.
    // Counts recognised lines, the same direction the blocks fill, or the two halves of the row disagree.
    documentTally(document) {
      const recognised = document.lines - document.unexplained;
      if (document.unexplained > 0) return `${this.count(recognised)} of ${this.count(document.lines)} lines`;
      return `${this.count(document.lines)} ${document.lines === 1 ? 'line' : 'lines'}`;
    },

    documentShare(document) {
      const recognised = document.lines - document.unexplained;
      return `${this.count(recognised)} of ${this.count(document.lines)} lines recognised`;
    },
    // Grouped explicitly rather than by browser locale, so a line count reads the same for everyone and
    // cannot come back as "4.651" for a reader whose locale swaps the separators.
    count(number) {
      return number.toLocaleString('en-US');
    },
    // Before a decision both buttons stay solid (a plain call to action). Once one is the stored decision
    // it keeps its solid colour and the other relaxes to an outline - quieter, but still obviously a button
    // the reviewer can click to switch.
    buttonClass(button) {
      if (this.selectedButtonId === null || this.selectedButtonId === button.id) return button.variant;
      return button.variant.replace('btn-', 'btn-outline-');
    },
    // A short one-shot pulse on the button that just became the decision, so a change registers right where
    // the cursor is even when accept/reject are toggled back and forth
    flashDecision(id) {
      if (id === null) return;
      if (this.flashTimer !== null) clearTimeout(this.flashTimer);
      this.flashId = null;
      this.$nextTick(() => {
        this.flashId = id;
        this.flashTimer = setTimeout(() => {
          this.flashId = null;
          this.flashTimer = null;
        }, 900);
      });
    },
    async loadTemplates() {
      try {
        const ua = new UserAgent({baseURL: window.location.href});
        const res = await ua.get('/comment-templates/all');
        if (res.isSuccess) this.templates = await res.json();
      } catch (err) {
        // Not being able to offer templates is no reason to bother the reviewer, the picker just stays hidden
      }
    },
    // The decision is posted as the form field the server expects ("acceptable"/"unacceptable"), but which
    // state that turns into is still derived server side from the reviewer's capability
    async submitReview(url, decision) {
      if (this.submitting) return;

      // A leftover placeholder is occasionally intentional, so this warns rather than blocks
      const unfilled = findPlaceholders(this.result);
      if (unfilled.length > 0) {
        const tokens = unfilled.map(p => p.name).join(', ');
        if (!window.confirm(`The comment still contains unfilled placeholders: ${tokens}. Submit anyway?`)) return;
      }

      this.submitting = true;
      this.submittingId = decision;

      const form = {comment: this.result, [decision]: 1};
      const limiting = decision === 'acceptable' && this.hasAdminRole === true;
      if (limiting) {
        form.limitation = this.withLimitation ? 1 : 0;
        form.limitations_seen = this.limitations.map(limitation => limitation.id).join(',');
      }
      const limitationsChange = limiting && this.withLimitation !== this.limitations.length > 0;

      try {
        const ua = new UserAgent({baseURL: window.location.href});
        const res = await ua.post(url, {form});

        let data = null;
        try {
          data = await res.json();
        } catch (e) {
          // Not JSON, an authentication failure renders an HTML page
        }

        if (res.isSuccess && data && data.ok) {
          this.$refs.toaster?.notify(`Reviewed ${data.name} as ${data.state}`);

          // Do not race the pending refresh timer, and do not update the state optimistically, the
          // stale local state is what makes refreshData() adopt the comment the server just stored
          this.cancelApiRefresh();
          this.limitationTouched = false;
          await this.doApiRefresh();
          if (limitationsChange) this.$emit('limitations-changed');

          // The refresh has flipped the selected button, now pulse it so the change is unmissable
          this.flashDecision(this.selectedButtonId);
          return;
        }

        const message = (data && data.error) || `Request failed (HTTP ${res.statusCode})`;
        this.$refs.toaster?.notify(message, 'danger', 5000);
      } catch (err) {
        this.$refs.toaster?.notify(`Review request failed: ${err}`, 'danger', 5000);
      } finally {
        this.submitting = false;
        this.submittingId = null;
      }
    },
    notifyError(message) {
      this.$refs.toaster?.notify(message, 'danger', 5000);
    },

    // The rebuild happens next to the report the reviewer is reading, so there is nothing to reload here.
    // The report area is told to enter its rebuild state instead, and the notice appearing under the
    // metadata is what confirms the click.
    async reindex() {
      this.reindexBusy = true;
      this.reindexFailed = false;
      try {
        const response = await fetch(this.reindexUrl, {method: 'POST', cache: 'no-store'});
        if (response.ok) {
          this.reindexBusy = false;
          this.reindexQueued = true;
          this.$emit('reindex-queued');
          return;
        }
      } catch (err) {
        console.error('Reindex request failed:', err);
      }
      this.reindexBusy = false;
      this.reindexFailed = true;
    },

    // The report area has swapped in the new report, which is the moment the button's answer changes.
    // Waiting for the next scheduled refresh would leave it advertising patterns that are already in.
    rebuildFinished() {
      this.reindexQueued = false;
      this.cancelApiRefresh();
      return this.doApiRefresh();
    },
    refreshData(data) {
      const copiedFiles = data.copied_files;
      for (const key of ['%doc', '%license']) {
        this.copiedFiles[key] = copiedFiles[key].length > 0 ? copiedFiles[key].map(displayName).join(' ') : null;
      }

      this.timestamps = {
        created: data.created,
        imported: data.imported,
        unpacked: data.unpacked,
        indexed: data.indexed,
        reviewed: data.reviewed,
        cleaned: data.cleaned
      };
      this.legalDocuments = data.legal_documents ?? null;
      this.derivedDocuments = data.documents;
      this.legalReviewNotices = data.legal_review_notices;

      this.externalLink = data.external_link;
      this.relatedReviews = data.related_reviews;

      this.declarations = data.declarations;
      const perFile = {};
      for (const d of this.declarations) perFile[d.file] = (perFile[d.file] ?? 0) + 1;
      for (const d of this.declarations) {
        d.fileUrl = fileViewUrl(this.pkgId, d.file);
        d.showName = perFile[d.file] > 1;
      }
      this.incompleteCheckout = data.incomplete_checkout.map(
        service => `Remote service in _service file: ${service.name} (mode: ${service.mode})`
      );

      this.pkgFamily = data.package_family;
      this.pkgName = data.package_name;
      this.pkgPriority = data.package_priority;
      this.pkgRisk = data.package_risk;
      this.pkgShortname = data.package_shortname;
      this.pkgSummary = data.package_summary;
      this.pkgUrl = data.package_url;
      this.pkgVersion = data.package_version;
      this.pkgEmbargoed = data.embargoed;
      this.tags = data.tags ?? [];
      this.canEditTags = data.can_edit_tags === true;
      this.canViewAudit = data.can_view_audit === true;
      if (this.canEditTags && this.knownTags.length === 0) this.loadKnownTags();
      this.pkgEphemeral = data.ephemeral;
      this.ephemeralDelete = data.ephemeral_delete ? moment(data.ephemeral_delete * 1000).fromNow() : '';
      this.pkgAiAssisted = data.ai_assisted;
      const rec = data.ai_recommendation;
      this.aiRecommendation = rec
        ? {...rec, ...AI_VERDICT_MESSAGES[rec.verdict], ...chatTime(moment(rec.created_epoch * 1000))}
        : null;

      this.pkgChecksum = data.package_checksum;
      this.checkoutUrl = `/reviews/file_view/${this.pkgId}`;

      this.newPatterns = data.should_reindex;
      this.reindexing = data.reindexing;

      if (data.products.length > 0) {
        this.productsHtml = data.products.map(name => productLink({name}, {blank: true})).join(', ');
      }
      // A product link would only repeat the Products row
      this.links = data.links.filter(link => !data.products.includes(link.text));

      if (data.reviewed !== null) this.reviewed = moment(data.reviewed * 1000).fromNow();
      this.reviewingUser = data.reviewing_user;
      this.searchUrl = `/search?q=${encodeURIComponent(this.pkgName)}`;

      // Make sure not to reset the comment field in the middle of a review (unless someone else changed the state)
      if (data.state !== this.state) this.result = data.result ?? '';
      this.notice = data.notice;
      this.state = data.state;
      this.limitations = data.limitations;
      if (!this.limitationTouched) this.withLimitation = this.limitations.length > 0;

      if (data.unpacked_files !== null) {
        this.unpackedFiles = data.unpacked_files;
        this.unpackedSize = data.unpacked_size;
      }

      // Initialise the target hover popovers once their icons have rendered (getOrCreateInstance keeps
      // repeated polls from stacking duplicates).
      this.$nextTick(setupPopoverDelayed);

      // This block sits above the report tabs, so its height decides where they end up. Anything
      // deep-linking to a tab has to wait for it.
      this.$emit('loaded');
    }
  }
};
</script>

<style>
.report-form {
  border: 1px solid var(--cavil-border);
  border-radius: 8px;
  margin-top: 1rem;
}
/* Raised like the glass badges: their gloss settling into the grey, a lit top edge and a faint shaded bottom one */
.report-form-head {
  --risk-emphasis: var(--cavil-risk-unknown-bg);
  --risk-glyph: var(--cavil-on-accent);
  --risk-layer: linear-gradient(transparent, transparent);
  align-items: center;
  background:
    var(--risk-layer),
    linear-gradient(180deg, var(--cavil-badge-gloss-top), var(--cavil-badge-gloss-bottom) 55%, transparent),
    var(--cavil-canvas-subtle);
  border-bottom: 1px solid var(--cavil-border);
  border-radius: 7px 7px 0 0;
  box-shadow:
    inset 0 1px 0 var(--cavil-badge-rim),
    inset 0 -1px 0 rgba(var(--cavil-shadow-rgb), 0.06);
  display: flex;
  gap: 1rem;
  padding: 1rem 1.25rem;
}
.report-form-avatar {
  align-items: center;
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-border);
  border-radius: 10px;
  box-shadow: 0 1px 2px rgba(var(--cavil-shadow-alt-rgb), 0.08);
  color: var(--cavil-fg-muted);
  display: flex;
  flex: 0 0 auto;
  font-size: 1.6rem;
  height: 3.5rem;
  justify-content: center;
  width: 3.5rem;
}
.report-form-title {
  min-width: 0;
}
/* The grade in a shield of Primer's emphasis colours, the shape compliance scanners use for a status. A number, not
   a check or cross, because risk is an input to the review and not its outcome. */
.report-risk {
  align-items: center;
  display: flex;
  gap: 0.85rem;
  margin-left: auto;
}
/* The risk washes its colour in from the shield's edge, the report's row wash idiom stretched across the title bar.
   Unrated and unknown take the annotation blue, a neutral highlight: a grey wash reads as depth in this UI. Each hue
   has its own strength, measured to look equally strong. */
.report-form-head.is-success,
.report-form-head.is-warning,
.report-form-head.is-danger,
.report-form-head.is-unknown {
  --risk-layer: linear-gradient(270deg, rgba(var(--risk-rgb), var(--risk-wash)), transparent 35%);
}
.report-form-head.is-unknown {
  --risk-rgb: var(--cavil-accent-rgb);
  --risk-wash: 0.078;
}
.report-form-head.is-success {
  --risk-wash: 0.088;
  --risk-rgb: var(--cavil-success-rgb);
  --risk-emphasis: var(--cavil-success-emphasis);
}
/* The priority badges' vivid amber, with a dark number like the old ribbon: Primer's attention emphasis
   comes out brown at this size */
.report-form-head.is-warning {
  --risk-wash: 0.07;
  --risk-rgb: var(--cavil-attention-vivid-rgb);
  --risk-emphasis: rgb(var(--cavil-attention-vivid-rgb));
  --risk-glyph: var(--cavil-fg);
}
.report-form-head.is-danger {
  --risk-wash: 0.08;
  --risk-rgb: var(--cavil-danger-rgb);
  --risk-emphasis: var(--cavil-danger);
}
[data-bs-theme='dark'] .report-form-head.is-unknown {
  --risk-wash: 0.08;
}
[data-bs-theme='dark'] .report-form-head.is-success {
  --risk-wash: 0.054;
}
[data-bs-theme='dark'] .report-form-head.is-warning {
  --risk-glyph: var(--cavil-canvas);
  --risk-wash: 0.065;
}
[data-bs-theme='dark'] .report-form-head.is-danger {
  --risk-wash: 0.072;
}
.report-risk-grade {
  display: grid;
  flex: 0 0 auto;
  height: 3.5rem;
  place-items: center;
  width: 3.05rem;
}
.report-risk-grade svg,
.report-risk-grade strong {
  grid-area: 1 / 1;
}
/* A struck metal badge in flat colour only: a hard ledge below for thickness, the right half one shade darker
   like a heraldic split, a fine rim stamped inside the edge, and the number pressed into it */
.report-risk-grade svg {
  height: 100%;
  overflow: visible;
  stroke-linejoin: round;
  width: 100%;
}
.report-risk-shield-ledge,
.report-risk-shield-base {
  fill: var(--risk-emphasis);
  stroke: var(--risk-emphasis);
  stroke-width: 3;
}
/* A mixed colour, not a filter: filters rasterize SVG shapes and blur them when zoomed */
.report-risk-shield-ledge {
  fill: color-mix(in srgb, var(--risk-emphasis) 70%, black);
  stroke: color-mix(in srgb, var(--risk-emphasis) 70%, black);
}
.report-risk-shield-facet {
  fill: rgba(0, 0, 0, 0.12);
}
.report-risk-shield-rim {
  fill: none;
  stroke: rgba(255, 255, 255, 0.45);
  stroke-width: 1.2;
}
/* Raised a little, the shield is widest above its middle */
.report-risk-grade strong {
  color: var(--risk-glyph);
  font-size: 1.45rem;
  font-weight: 700;
  line-height: 1;
  margin-bottom: 0.35rem;
  text-shadow:
    0 -1px 0 rgba(0, 0, 0, 0.25),
    0 1px 0 rgba(255, 255, 255, 0.2);
}
/* A field like the others, label and help above the value, mirroring the name and summary on the left */
.report-risk-text {
  display: flex;
  flex-direction: column;
  text-align: right;
}
.report-risk-description {
  color: var(--cavil-fg);
  font-size: 1.15rem;
  font-weight: 600;
  letter-spacing: -0.01em;
  line-height: 1.3;
  white-space: nowrap;
}
.report-risk-label {
  color: var(--cavil-fg-muted);
  font-size: 12px;
  font-weight: 600;
  line-height: 1.3;
  margin-bottom: 0.2rem;
}
.report-metadata-list dt .cavil-notice-help-button,
.report-risk-label .cavil-notice-help-button {
  color: var(--cavil-fg-subtle);
  margin-left: 0.25rem;
}
/* A soft shade falling from the top rule, like the compatibility matrix's explanation panel, setting the timeline
   apart from the fields. Shorter and stronger than there, a grey surface swallows the matrix values. */
.report-form-foot {
  background: var(--cavil-canvas-subtle);
  border-radius: 0 0 8px 8px;
  border-top: 1px solid var(--cavil-border);
  box-shadow: inset 0 7px 9px -7px rgba(var(--cavil-shadow-cool-rgb), 0.22);
  padding: 1rem 1.25rem 0.85rem;
}
.report-metadata-summary {
  color: var(--cavil-fg-muted);
  margin: 0.25rem 0 0;
}
.report-metadata-name {
  font-size: 1.5rem;
  font-weight: 600;
  letter-spacing: -0.01em;
  margin: 0;
  min-width: 0;
  overflow-wrap: break-word;
}
.report-metadata-name a {
  color: var(--cavil-fg);
  text-decoration: none;
}
.report-metadata-name a:hover,
.report-metadata-name a:focus {
  color: var(--cavil-accent);
}
.report-metadata-name .report-metadata-id {
  color: var(--cavil-fg-subtle);
  font-family: inherit;
  font-size: inherit;
  font-weight: 300;
  margin-left: 0.3rem;
}
.report-metadata-list {
  color: var(--cavil-fg);
  display: flex;
  font-feature-settings: 'liga', 'kern';
  font-size: 15px;
  font-variant-numeric: tabular-nums;
  line-height: 1.5;
  margin: 0;
}
.report-metadata-list + .report-metadata-list {
  border-top: 1px solid var(--cavil-border-muted);
}
/* Every row shares the 50% line: the left half holds one field, the right half one field or two quarters.
   The last field takes the rest. */
.report-form-field {
  flex: 0 0 25%;
  min-width: 0;
  padding: 0.75rem 1rem;
}
.report-form-field + .report-form-field {
  border-left: 1px solid var(--cavil-border-muted);
}
/* Admin details, read rarely: last row, muted so it stays out of the reviewer's way */
.report-metadata-list.is-secondary dd {
  color: var(--cavil-fg-muted);
}
.report-form-field.is-wide {
  flex-basis: 50%;
}
.report-form-field:last-child {
  flex-grow: 1;
}
.report-metadata-list dt {
  color: var(--cavil-fg-muted);
  font-size: 12px;
  font-weight: 600;
  line-height: 1.3;
  margin-bottom: 0.25rem;
}
.report-metadata-list dd {
  margin: 0;
  overflow-wrap: anywhere;
}
.report-metadata-list a:not(.cavil-external-link-target) {
  color: var(--cavil-accent);
  text-decoration: none;
  text-underline-offset: 2px;
}
.report-metadata-list a:not(.cavil-external-link-target):hover,
.report-metadata-list a:not(.cavil-external-link-target):focus {
  text-decoration: underline;
}
.report-metadata-list small {
  color: var(--cavil-fg-disabled);
  font-size: 12px;
  font-weight: 400;
}
.report-metadata-list .badge {
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.01em;
  padding: 0.4em 0.65em;
  vertical-align: baseline;
}
/* A fact that needs attention tints its whole cell, like the risk pane, instead of carrying a badge */
.report-form-field.is-flagged {
  background: color-mix(in srgb, var(--cavil-attention-bg) 60%, var(--cavil-canvas));
}
.report-form-field.is-flagged dd i {
  color: var(--cavil-attention);
  margin-right: 0.4rem;
}
.report-ephemeral-hint {
  color: var(--cavil-fg-muted);
  font-size: 13px;
  margin-left: 0.4rem;
}
.report-metadata-links {
  align-items: flex-start;
  display: flex;
  flex-wrap: wrap;
  gap: 0.4rem 0.5rem;
}
.report-metadata-link.is-closed {
  opacity: 0.6;
}
.report-metadata-link {
  display: inline-flex;
  flex: 0 0 auto;
  max-width: 100%;
  min-width: 0;
}
/* Tags, comment and decision buttons share one box like the GitHub comment composer, so the inner
   TagInput and CommentEditor borders are neutralised and become dividers */
.report-review-box {
  border: 1px solid var(--cavil-border);
  border-radius: 8px;
  margin: 1.25rem 0;
}
.report-review-box:has(.package-tags-bar:focus-within, .comment-editor:focus-within) {
  border-color: var(--cavil-accent);
  box-shadow: 0 0 0 3px rgba(var(--cavil-accent-rgb), 0.18);
}
#pkg-review .comment-editor {
  border: 0;
  border-radius: 0;
  box-shadow: none;
}
#pkg-review:first-child .comment-editor {
  border-top-left-radius: 7px;
  border-top-right-radius: 7px;
}
#pkg-review .metadata-review-editor:last-child .comment-editor {
  border-bottom-left-radius: 7px;
  border-bottom-right-radius: 7px;
}
.package-tags-bar {
  align-items: stretch;
  border-bottom: 1px solid var(--cavil-border);
  display: flex;
  position: relative;
}
/* Anchor TagInput's autocomplete popover to the whole bar (not the input segment right of the label) so it
   spans full width and drops below the bar instead of starting mid-bar. */
.package-tags-body .tag-input {
  position: static;
}
.package-tags-label {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border-radius: 7px 0 0 0;
  border-right: 1px solid var(--cavil-border);
  color: var(--cavil-fg);
  display: flex;
  flex: 0 0 auto;
  font-size: 13px;
  font-weight: 600;
  padding: 0.45rem 0.75rem;
}
.package-tags-body {
  flex: 1 1 auto;
  min-width: 0;
  padding: 0.4rem 0.6rem;
}
.package-tags-body .report-note-tag-editor {
  background: transparent;
  border: 0;
  border-radius: 0;
  margin-bottom: 0;
  padding: 0;
}
.package-tags-body .report-note-tag-editor:focus-within {
  box-shadow: none;
}
.package-tags-readonly {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
}
#pkg-tags .report-note-tag.report-cve-tag {
  background: var(--cavil-danger-bg);
  border-color: var(--cavil-danger-border);
  color: var(--cavil-danger);
}
.report-metadata-id {
  border-radius: 6px;
  color: var(--cavil-fg);
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 14px;
  padding: 0.05rem 0.35rem;
  transition:
    background-color 0.15s ease,
    color 0.15s ease;
}
.report-metadata-id:hover,
.report-metadata-id:focus {
  background: var(--cavil-canvas-subtle);
  color: var(--cavil-accent);
  outline: none;
}
#pkg-shortname,
#checkout-url a {
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 14px;
}
@media (max-width: 700px) {
  .report-form-head {
    flex-wrap: wrap;
  }
  .report-metadata-list {
    flex-direction: column;
  }
  .report-form-field + .report-form-field {
    border-left: 0;
    border-top: 1px solid var(--cavil-border-muted);
  }
}
.metadata-count-pill {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 999px;
  color: var(--cavil-fg-muted);
  display: inline-flex;
  font-size: 12px;
  font-weight: 600;
  line-height: 1;
  padding: 0.35rem 0.6rem;
  text-decoration: none;
  white-space: nowrap;
}
.metadata-count-pill:hover,
.metadata-count-pill:focus {
  background: var(--cavil-accent-tint-1);
  border-color: var(--cavil-accent-border);
  color: var(--cavil-accent);
  text-decoration: none;
}
/* Overflow is clipped at the padding edge, so bottom padding would show the top of the fifth line */
.legal-review-notice-clamped {
  -webkit-box-orient: vertical;
  border-bottom: 0.75rem solid var(--cavil-canvas);
  display: -webkit-box;
  -webkit-line-clamp: 4;
  overflow: hidden;
  padding-bottom: 0;
}
.cavil-notice-item.legal-document-item {
  align-items: baseline;
  display: flex;
  gap: 0.85rem;
  white-space: normal;
}
.cavil-notice-item.legal-document-item,
#legal-documents .list-more-toggle {
  background: linear-gradient(90deg, rgba(var(--cavil-success-rgb), 0.08), var(--cavil-canvas) 2.5rem);
}
.cavil-notice-item.legal-document-item:hover,
#legal-documents .list-more-toggle:hover {
  background: linear-gradient(90deg, rgba(var(--cavil-success-rgb), 0.12), var(--cavil-canvas-subtle) 2.5rem);
}
/* A wash needs a light canvas to read as a tint; over near-black it only ever comes out as
   grey haze. Dark marks the row the way the risk bands already do, with a thin inset rule. */
[data-bs-theme='dark'] .cavil-notice-item.legal-document-item,
[data-bs-theme='dark'] #legal-documents .list-more-toggle {
  background: var(--cavil-canvas);
  box-shadow: inset 2px 0 0 var(--cavil-success-emphasis);
}
[data-bs-theme='dark'] .cavil-notice-item.legal-document-item:hover,
[data-bs-theme='dark'] #legal-documents .list-more-toggle:hover {
  background: var(--cavil-canvas-subtle);
}
/* File names follow the report's convention: muted until hovered, where they turn link-blue */
.legal-document-path {
  color: var(--cavil-fg-muted);
  flex: 1 1 auto;
  font-size: 13px;
  font-weight: 500;
  line-height: 1.35;
  min-width: 0;
  overflow-wrap: anywhere;
  text-decoration-color: transparent;
}
.legal-document-path:hover,
.legal-document-path:focus {
  color: var(--cavil-accent-strong);
  text-decoration-color: currentColor;
}
.legal-document-lines {
  /* The mark has no text of its own, so its baseline is its bottom edge: it sits on the annotation's
     baseline, where it sat when it was part of that text run. Stretch would hang it from the top. */
  align-items: baseline;
  color: var(--cavil-fg-subtle);
  display: flex;
  flex: 0 0 auto;
  font-size: 12px;
  font-variant-numeric: tabular-nums;
  gap: 0.6rem;
  white-space: nowrap;
}
/* GitHub's diffstat mark: proportion beside the count, never instead of it. Amber rather than red, which
   would grade text that is only unmatched, and green/red is the one pair some readers cannot separate.
   A covered file marks five greys rather than nothing, which is what amber is read against. */
.legal-document-meter {
  display: inline-flex;
  gap: 2px;
}
.legal-document-block {
  background: var(--cavil-border);
  border-radius: 1px;
  height: 8px;
  width: 8px;
}
.legal-document-block.is-covered {
  background: var(--cavil-success);
}
/* Breaks inside a word only when nothing else fits, so the grid cannot squeeze a column below its longest word */
#pkg-declarations {
  align-items: baseline;
  overflow-wrap: break-word;
  display: grid;
  gap: 0.25rem 1rem;
  grid-template-columns: repeat(3, auto);
  justify-content: start;
}
#pkg-declarations.metadata-declarations-named {
  grid-template-columns: repeat(4, auto);
}
.metadata-declaration {
  display: contents;
}
.metadata-declaration-name,
.metadata-declaration-undeclared,
.report-metadata-list a.metadata-declaration-file,
.report-metadata-list a.metadata-history-link {
  color: var(--cavil-fg-muted);
  font-size: 13px;
}
.report-metadata-list a.metadata-declaration-file:hover,
.report-metadata-list a.metadata-declaration-file:focus,
#related-reviews,
#pkg-products a,
#checkout-url a {
  color: var(--cavil-fg);
}
.report-metadata-list a.metadata-history-link:hover,
.report-metadata-list a.metadata-history-link:focus,
#related-reviews:hover,
#related-reviews:focus,
#pkg-products a:hover,
#pkg-products a:focus,
#checkout-url a:hover,
#checkout-url a:focus {
  color: var(--cavil-accent);
}
.report-metadata-list a.metadata-history-link {
  margin-left: 8px;
}
.metadata-declaration-format {
  background: var(--cavil-canvas-subtle);
  border: 1px solid var(--cavil-border);
  border-radius: 999px;
  color: var(--cavil-fg-muted);
  font-size: 11px;
  font-weight: 600;
  justify-self: start;
  letter-spacing: 0.03em;
  line-height: 1;
  padding: 0.3rem 0.55rem;
  text-transform: uppercase;
  white-space: nowrap;
}
/* Review-information card. Rendered as a terminal/console panel - a small
   dark title bar with a prompt-style caret + label, then the freeform
   monospace body as if it were tool output. Visually distinct from the
   surrounding notice stack so reviewers and packagers can't miss it,
   regardless of whether the body is a single sentence or a multi-line diff. */
.review-information-card {
  background: var(--cavil-canvas);
  border: 1px solid var(--cavil-review-card-border);
  border-radius: 6px;
  margin: 1.25rem 0;
  overflow: hidden;
}
.review-information-card-bar {
  align-items: center;
  background: var(--cavil-inverse-bg-alt);
  color: var(--cavil-inverse-fg-subtle);
  display: flex;
  font-size: 12px;
  font-weight: 500;
  gap: 0.45rem;
  letter-spacing: 0.04em;
  padding: 0.45rem 0.85rem;
  text-transform: lowercase;
}
.review-information-card-bar i {
  color: var(--cavil-grey-4);
  font-size: 11px;
}
.help-example .legal-document-item {
  pointer-events: none;
}
.review-information-card-bar .cavil-notice-help-button:hover i,
.review-information-card-bar .cavil-notice-help-button:focus-visible i {
  color: var(--cavil-inverse-fg);
}
/* The compared report id links to that report, but stays typographically
   part of the tool output - only an underline on hover gives it away. */
.review-information-card-body a {
  color: inherit;
  text-decoration: none;
}
.review-information-card-body a:hover,
.review-information-card-body a:focus {
  text-decoration: underline;
}
.review-information-card-body {
  color: var(--cavil-fg);
  font-family: ui-monospace, SFMono-Regular, Consolas, 'Liberation Mono', Menlo, monospace;
  font-size: 13px;
  line-height: 1.55;
  margin: 0;
  overflow-x: auto;
  padding: 0.85rem 0.95rem;
  white-space: pre-wrap;
}
#spec-legal-review-notices:has(.cavil-notice-list) .cavil-notice-heading > i:first-child {
  color: var(--cavil-success);
}
.ai-recommendation {
  align-items: flex-start;
  color: var(--cavil-fg);
  display: flex;
  gap: 14px;
  margin: 1.25rem 0;
  text-decoration: none;
}
.ai-recommendation:hover {
  color: var(--cavil-fg);
}
.ai-recommendation-avatar {
  flex: none;
  height: 40px;
  overflow: visible;
  width: 40px;
}
.ai-recommendation-avatar line,
.ai-recommendation-avatar rect,
.ai-recommendation-mouth {
  fill: none;
  stroke: var(--cavil-fg-muted);
  stroke-linecap: round;
  stroke-width: 1.6;
}
.ai-recommendation-avatar .ai-recommendation-head {
  fill: var(--cavil-accent-bg);
}
.ai-recommendation-avatar .ai-recommendation-ear {
  fill: var(--cavil-canvas);
}
.ai-recommendation-antenna {
  fill: var(--cavil-attention-strong);
}
.ai-recommendation-eyes {
  animation: ai-recommendation-blink 6s infinite;
  fill: var(--cavil-fg);
  transform-box: fill-box;
  transform-origin: center;
}
@keyframes ai-recommendation-blink {
  0%,
  94%,
  100% {
    transform: scaleY(1);
  }
  97% {
    transform: scaleY(0.1);
  }
}
.ai-recommendation-wave {
  fill: none;
  opacity: 0;
  stroke: var(--cavil-attention-strong);
  stroke-linecap: round;
  stroke-width: 1.2;
}
.ai-recommendation-waves .ai-recommendation-wave {
  animation: ai-recommendation-waves 6s infinite;
}
.ai-recommendation-waves .ai-recommendation-wave + .ai-recommendation-wave {
  animation-delay: 0.3s;
}
@keyframes ai-recommendation-waves {
  0%,
  20%,
  40%,
  100% {
    opacity: 0;
  }
  8%,
  28% {
    opacity: 1;
  }
}
.ai-recommendation-stalk {
  transform-box: view-box;
  transform-origin: 16px 9px;
}
.ai-recommendation-wobble .ai-recommendation-stalk {
  animation: ai-recommendation-wobble 6s infinite;
}
@keyframes ai-recommendation-wobble {
  0%,
  30%,
  100% {
    transform: rotate(0);
  }
  5% {
    transform: rotate(14deg);
  }
  10% {
    transform: rotate(-10deg);
  }
  15% {
    transform: rotate(7deg);
  }
  20% {
    transform: rotate(-4deg);
  }
  25% {
    transform: rotate(2deg);
  }
}
.ai-recommendation-double-blink .ai-recommendation-eyes {
  animation-name: ai-recommendation-double-blink;
}
@keyframes ai-recommendation-double-blink {
  0%,
  88%,
  91%,
  94%,
  100% {
    transform: scaleY(1);
  }
  89.5%,
  97% {
    transform: scaleY(0.1);
  }
}
@media (prefers-reduced-motion: reduce) {
  .ai-recommendation-eyes {
    animation: none;
  }
}
.ai-recommendation-bubble {
  align-items: center;
  background: var(--cavil-accent-tint-1);
  border: 1px solid var(--cavil-accent-border);
  border-radius: 14px;
  display: flex;
  flex: 1;
  gap: 16px;
  min-width: 0;
  padding: 10px 12px 10px 16px;
  position: relative;
}
.ai-recommendation-bubble::before,
.ai-recommendation-bubble::after {
  border: 8px solid transparent;
  border-left: 0;
  content: '';
  left: -8px;
  position: absolute;
  top: 12px;
}
.ai-recommendation-bubble::before {
  border-right-color: var(--cavil-accent-border);
}
.ai-recommendation-bubble::after {
  border-right-color: var(--cavil-accent-tint-1);
  left: -7px;
}
.ai-recommendation-speech {
  flex: 1;
  min-width: 0;
}
.ai-recommendation-says {
  font-size: 15px;
}
.ai-recommendation-meta {
  color: var(--cavil-fg-muted);
  font-size: 12px;
  margin-top: 2px;
}
.ai-recommendation-says strong {
  font-weight: 600;
}
.ai-recommendation-success {
  color: var(--cavil-success);
}
.ai-recommendation-attention {
  color: var(--cavil-attention);
}
.ai-recommendation-danger {
  color: var(--cavil-danger);
}
.ai-recommendation-more {
  background: var(--cavil-accent-bg);
  border: 1px solid var(--cavil-accent-border);
  border-radius: 2em;
  color: var(--cavil-accent-strong);
  flex: none;
  font-size: 12px;
  font-weight: 500;
  line-height: 22px;
  padding: 0 10px;
  transition: background-color 0.15s;
}
.ai-recommendation-more i {
  font-size: 10px;
  margin-left: 2px;
}
.ai-recommendation:hover .ai-recommendation-more {
  background: var(--cavil-accent-border);
}
.metadata-review-actions {
  align-items: center;
  background: var(--cavil-canvas-subtle);
  border-radius: 0 0 7px 7px;
  border-top: 1px solid var(--cavil-border);
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  padding: 0.6rem 0.75rem;
}
.metadata-review-actions .btn {
  border-radius: 6px;
  font-size: 13px;
  font-weight: 600;
  position: relative;
}
.metadata-review-status {
  align-items: center;
  color: var(--cavil-fg);
  display: flex;
  flex: 1;
  font-size: 13px;
  gap: 0.5rem;
}
.metadata-review-status-icon {
  color: var(--cavil-success);
}
.metadata-review-status.is-unacceptable .metadata-review-status-icon {
  color: var(--cavil-danger);
}
.metadata-review-status strong {
  font-weight: 600;
}
.metadata-review-status-detail {
  color: var(--cavil-fg-muted);
  font-size: 12px;
  margin-left: auto;
}
.metadata-review-actions-group {
  align-items: center;
  display: inline-flex;
  flex-wrap: wrap;
}
.metadata-review-actions-group > span {
  display: inline-flex;
}
.metadata-review-actions-group > * + * {
  margin-left: -1px;
}
.metadata-review-actions-group > *:not(:first-child) .btn,
.metadata-review-actions-group > .btn:not(:first-child) {
  border-bottom-left-radius: 0;
  border-top-left-radius: 0;
}
.metadata-review-actions-group > *:not(:last-child) .btn,
.metadata-review-actions-group > .btn:not(:last-child) {
  border-bottom-right-radius: 0;
  border-top-right-radius: 0;
}
.metadata-review-actions .btn:hover,
.metadata-review-actions .btn:focus {
  z-index: 1;
}
.metadata-review-actions .btn i {
  margin-right: 0.4em;
}
/* The button that reflects the stored decision keeps its solid fill and sits above its outlined
   neighbour so its border reads as a single unbroken segment */
.metadata-review-actions .btn.is-decision-current {
  z-index: 1;
}
/* One-shot pulse when a decision is made or switched, drawing the eye to the button under the cursor */
.metadata-review-actions .btn.is-decision-flash {
  animation: metadata-decision-flash 0.7s ease;
}
@keyframes metadata-decision-flash {
  0% {
    filter: brightness(1);
  }
  35% {
    filter: brightness(1.4);
  }
  100% {
    filter: brightness(1);
  }
}
@media (prefers-reduced-motion: reduce) {
  .metadata-review-actions .btn.is-decision-flash {
    animation: none;
  }
}
.metadata-review-actions-secondary {
  margin-left: auto;
}
/* Nearly every review has no limitation, so the box stays a muted label until it would change something, and then
   the label just continues with what accepting will do */
.metadata-review-limitation {
  align-items: baseline;
  color: var(--cavil-fg-muted);
  display: flex;
  font-size: 13px;
  gap: 0.35rem;
  min-width: 0;
}
.metadata-review-limitation label {
  cursor: pointer;
  flex: none;
  margin: 0;
}
.metadata-review-limitation label.is-checked {
  color: var(--cavil-fg);
}
.metadata-review-limitation .form-check-input {
  margin: 0 0.4rem 0 0;
  vertical-align: -0.15em;
}
.metadata-review-limitation-effect::before {
  content: '·';
  margin-right: 0.35rem;
}
.metadata-review-limitation-effect i {
  margin-right: 0.3rem;
}
.metadata-review-limitation-effect a {
  color: inherit;
  text-decoration: none;
}
.metadata-review-limitation-effect a:hover,
.metadata-review-limitation-effect a:focus {
  color: var(--cavil-accent);
  text-decoration: underline;
}
.metadata-review-limitation-effect.is-removing {
  color: var(--cavil-danger);
}
.metadata-review-limitation-effect.is-removing::before {
  color: var(--cavil-fg-muted);
}
@media (max-width: 700px) {
  .metadata-review-status-detail {
    flex-basis: calc(100% - 1.5rem);
    margin-left: 1.5rem;
  }
  .metadata-review-status {
    flex-wrap: wrap;
  }
}
.cavil-classification-badge {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 0.5rem;
  border-radius: 1rem;
  background-color: var(--cavil-accent-deep-2);
  color: var(--cavil-canvas);
  width: 150px;
}
</style>
