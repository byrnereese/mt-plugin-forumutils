<?php
function smarty_function_mtentrypromotedfromcommentid($args, &$ctx) {
  $entry = $ctx->stash('entry');
  return $entry['promoted_from_comment_id'];
}
?> 

