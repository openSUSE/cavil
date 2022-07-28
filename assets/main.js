import './sass/app.scss';
import 'bootstrap/dist/css/bootstrap.css';
import 'datatables.net-bs4/css/dataTables.bootstrap4.css';
import 'codemirror/lib/codemirror.css';
import 'codemirror/theme/neo.css';

import 'timeago';
import 'bootstrap';
import 'datatables.net';
import 'datatables.net-bs4';
import 'codemirror';

import {setupCodeMirrorForFile} from './legacy/file.js';
import {backToTop} from './legacy/nav.js';
import {setupCreatePattern} from './legacy/patterns.js';
import {setupProductTable} from './legacy/product.js';
import {setupRecentTable} from './legacy/recent.js';
import {setupReviewDetails, setupReviewTable} from './legacy/review.js';
import {setupCodeMirrorForSnippet} from './legacy/snippet.js';
import {fromNow} from './legacy/time.js';
import {createLicense, ignoreLine, snippetNonLicense, snippetSwitcher} from './legacy/util.js';
import $ from 'jquery';

window.$ = $;

window.legacy = {
  fireIndex: undefined,
  fires: undefined,
  myCodeMirror: undefined,

  backToTop,
  createLicense,
  fromNow,
  ignoreLine,
  setupCodeMirrorForFile,
  setupCodeMirrorForSnippet,
  setupCreatePattern,
  setupRecentTable,
  setupProductTable,
  setupReviewDetails,
  setupReviewTable,
  snippetNonLicense,
  snippetSwitcher
};
