<?php
/**
 * Plugin Name: DrishtiBution Opportunities
 * Description: Registers Opportunities / News Bulletins and syncs published posts to Firebase.
 * Version: 0.1.0
 */

if (!defined('ABSPATH')) exit;

define('DRISHTI_OPPORTUNITY_WEBHOOK_URL', 'https://asia-south1-haathloom.cloudfunctions.net/receiveOpportunityWebhook');

add_action('init', function () {
    register_post_type('opportunity', [
        'labels' => [
            'name' => 'Opportunities / News Bulletins',
            'singular_name' => 'Opportunity / News Bulletin',
        ],
        'public' => true,
        'show_in_rest' => true,
        'menu_icon' => 'dashicons-megaphone',
        'supports' => ['title', 'editor', 'excerpt'],
        'has_archive' => true,
    ]);
});

function drishti_opportunity_fields() {
    return [
        'opportunity_type' => 'Type: job, education, training, or scheme',
        'organization_name' => 'Organization name',
        'summary' => 'One-line summary',
        'source_url' => 'Source URL',
        'eligibility_text' => 'Eligibility criteria',
        'deadline' => 'Application deadline',
        'application_url' => 'Application URL',
        'contact_email' => 'Contact email',
        'contact_phone' => 'Contact phone',
        'language' => 'Language',
        'address' => 'Address',
        'city' => 'City',
        'district' => 'District',
        'state' => 'State',
        'country' => 'Country',
        'employer' => 'Job employer',
        'role' => 'Job role',
        'employment_type' => 'Employment type',
        'experience' => 'Experience',
        'skills' => 'Skills',
        'salary_text' => 'Salary',
        'institution' => 'Education institution',
        'program' => 'Course or program',
        'level' => 'Education level',
        'duration' => 'Duration',
        'fee_text' => 'Fees',
        'provider' => 'Training or scheme provider',
        'mode' => 'Training mode',
        'benefits_text' => 'Scheme benefits',
        'application_process' => 'Application process',
    ];
}

add_action('add_meta_boxes', function () {
    add_meta_box('drishti_opportunity_details', 'DrishtiBution opportunity fields', 'drishti_render_opportunity_meta_box', 'opportunity', 'normal', 'high');
});

function drishti_render_opportunity_meta_box($post) {
    wp_nonce_field('drishti_save_opportunity', 'drishti_opportunity_nonce');
    foreach (drishti_opportunity_fields() as $key => $label) {
        $value = get_post_meta($post->ID, '_drishti_' . $key, true);
        echo '<p><label for="drishti_' . esc_attr($key) . '"><strong>' . esc_html($label) . '</strong></label>';
        if ($key === 'opportunity_type') {
            echo '<select class="widefat" id="drishti_' . esc_attr($key) . '" name="drishti_' . esc_attr($key) . '">';
            foreach (['job', 'education', 'training', 'scheme'] as $type) {
                echo '<option value="' . esc_attr($type) . '" ' . selected($value, $type, false) . '>' . esc_html(ucfirst($type)) . '</option>';
            }
            echo '</select>';
        } else {
            echo '<input class="widefat" id="drishti_' . esc_attr($key) . '" name="drishti_' . esc_attr($key) . '" value="' . esc_attr($value) . '">';
        }
        echo '</p>';
    }
}

add_action('save_post_opportunity', function ($post_id, $post, $update) {
    if (defined('DOING_AUTOSAVE') && DOING_AUTOSAVE) return;
    if (!current_user_can('edit_post', $post_id)) return;
    if (!isset($_POST['drishti_opportunity_nonce']) || !wp_verify_nonce($_POST['drishti_opportunity_nonce'], 'drishti_save_opportunity')) return;
    foreach (array_keys(drishti_opportunity_fields()) as $key) {
        if (isset($_POST['drishti_' . $key])) update_post_meta($post_id, '_drishti_' . $key, sanitize_textarea_field(wp_unslash($_POST['drishti_' . $key])));
    }
    if ($post->post_status === 'publish') drishti_send_opportunity_webhook($post_id, $update ? 'update' : 'publish');
}, 10, 3);

function drishti_send_opportunity_webhook($post_id, $action) {
    $post = get_post($post_id);
    $meta = function ($key) use ($post_id) { return trim((string) get_post_meta($post_id, '_drishti_' . $key, true)); };
    $type = $meta('opportunity_type');
    if (!in_array($type, ['job', 'education', 'training', 'scheme'], true)) return;
    $payload = [
        'event' => ['source' => 'wordpress', 'action' => $action, 'postId' => (int) $post_id, 'status' => 'publish', 'occurredAt' => gmdate('c')],
        'opportunity' => [
            'title' => get_the_title($post_id), 'type' => $type,
            'summary' => $meta('summary') ?: get_the_excerpt($post_id),
            'description' => wp_strip_all_tags($post->post_content),
            'organizationName' => $meta('organization_name'), 'sourceUrl' => $meta('source_url') ?: get_permalink($post_id),
            'eligibilityText' => $meta('eligibility_text'), 'deadline' => $meta('deadline'), 'applicationUrl' => $meta('application_url'),
            'contactEmail' => $meta('contact_email'), 'contactPhone' => $meta('contact_phone'), 'language' => $meta('language'),
            'location' => ['address' => $meta('address'), 'city' => $meta('city'), 'district' => $meta('district'), 'state' => $meta('state'), 'country' => $meta('country')],
        ],
    ];
    $map = ['employer' => 'employer', 'role' => 'role', 'employment_type' => 'employmentType', 'experience' => 'experience', 'skills' => 'skills', 'salary_text' => 'salaryText', 'institution' => 'institution', 'program' => 'program', 'level' => 'level', 'duration' => 'duration', 'fee_text' => 'feeText', 'provider' => 'provider', 'mode' => 'mode', 'benefits_text' => 'benefitsText', 'application_process' => 'applicationProcess'];
    foreach ($map as $field => $json_key) $payload['opportunity'][$json_key] = $meta($field);
    $body = wp_json_encode($payload);
    $secret = defined('DRISHTI_OPPORTUNITIES_WEBHOOK_SECRET') ? DRISHTI_OPPORTUNITIES_WEBHOOK_SECRET : '';
    if (!$secret) return;
    wp_remote_post(DRISHTI_OPPORTUNITY_WEBHOOK_URL, ['timeout' => 15, 'blocking' => false, 'headers' => ['Content-Type' => 'application/json', 'X-Drishti-Webhook-Signature' => hash_hmac('sha256', $body, $secret)], 'body' => $body]);
}